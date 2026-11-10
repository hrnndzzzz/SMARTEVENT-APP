import uuid
import calendar
from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.dependencies import (
    assert_record_scope,
    require_operational_read,
    scope_query_by_department,
)
from app.models import Category, Event, Expense, IncomeRecord, Receipt, User
from app.routers.analytics import for_organization
from app.services.academic_year import institution_today, validate_school_year
from app.schemas import (
    CategoryReport,
    ConsolidatedFinancialReport,
    EventReport,
    EventScope,
    FinancialEventSummary,
    Semester,
    IncomeSourceSummary,
)

router = APIRouter(prefix="/reports", tags=["reports"])


def _sum_amounts(records):
    return sum((Decimal(str(record.amount)) for record in records), Decimal("0.00"))


def _income_sources(records):
    groups = defaultdict(list)
    for income in records:
        groups[(income.source_type, income.source)].append(income)
    return [IncomeSourceSummary(source_type=kind, source=source,
                income_count=len(rows), total_income=_sum_amounts(rows))
            for (kind, source), rows in sorted(groups.items())]


@router.get("/category/{category_id}", response_model=CategoryReport)
def get_category_report(
    category_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")
    assert_record_scope(current_user, category, allow_officer_read=True)

    expense_query = scope_query_by_department(db.query(Expense), Expense.department_id, current_user)
    total_spent = (
        expense_query.with_entities(func.coalesce(func.sum(Expense.amount), 0))
        .filter(Expense.category_id == category_id, Expense.status == "approved")
        .scalar()
    )

    counts = dict(
        expense_query.with_entities(Expense.status, func.count(Expense.id))
        .filter(Expense.category_id == category_id)
        .group_by(Expense.status)
        .all()
    )

    return CategoryReport(
        category_id=category.id,
        category_name=category.name,
        allocated_budget=float(category.allocated_budget),
        remaining_budget=float(category.remaining_budget),
        total_spent=float(total_spent),
        approved_expense_count=counts.get("approved", 0),
        pending_expense_count=counts.get("pending", 0),
        rejected_expense_count=counts.get("rejected", 0),
    )


@router.get("/event/{event_id}", response_model=EventReport)
def get_event_report(
    event_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    event = db.query(Event).filter(Event.id == event_id).first()
    if event is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    assert_record_scope(current_user, event, allow_officer_read=True)

    expense_query = scope_query_by_department(db.query(Expense), Expense.department_id, current_user)
    expenses = (
        expense_query
        .filter(Expense.event_id == event_id)
        .order_by(Expense.created_at)
        .all()
    )
    incomes = (
        db.query(IncomeRecord)
        .options(selectinload(IncomeRecord.receipt))
        .filter(IncomeRecord.event_id == event_id)
        .order_by(IncomeRecord.received_on, IncomeRecord.created_at)
        .all()
    )

    total_spent = _sum_amounts(e for e in expenses if e.status == "approved")
    withheld = [income for income in incomes if income.receipt_review_status in {"pending", "rejected"}]
    eligible = [income for income in incomes if income.receipt_review_status not in {"pending", "rejected"}]
    total_income = _sum_amounts(eligible)
    receipt_query = scope_query_by_department(db.query(Receipt), Receipt.department_id, current_user)

    return EventReport(
        event_id=event.id,
        school_year=event.school_year,
        semester=event.semester,
        event_scope=event.event_scope,
        title=event.title,
        status=event.status,
        estimated_cost=float(event.estimated_cost),
        allocated_budget=float(event.allocated_budget),
        remaining_budget=float(event.remaining_budget),
        total_income=total_income,
        total_spent=total_spent,
        net_balance=total_income - total_spent,
        income_by_source=_income_sources(eligible),
        withheld_income_total=_sum_amounts(withheld),
        withheld_income_count=len(withheld),
        receipts=receipt_query.filter(Receipt.event_id == event_id).order_by(Receipt.created_at).all(),
        incomes=incomes,
        expenses=expenses,
    )


def _calendar_window(
    period: Literal["weekly", "monthly"],
    reference_date: date,
) -> tuple[date, date]:
    if period == "weekly":
        start_date = reference_date - timedelta(days=reference_date.weekday())
        return start_date, start_date + timedelta(days=6)

    start_date = reference_date.replace(day=1)
    end_day = calendar.monthrange(reference_date.year, reference_date.month)[1]
    return start_date, reference_date.replace(day=end_day)


@router.get("/financial", response_model=ConsolidatedFinancialReport)
def get_consolidated_financial_report(
    period: Literal["weekly", "monthly", "school_year", "semester"],
    reference_date: date | None = None,
    school_year: str | None = Query(default=None, pattern=r"^\d{4}-\d{4}$"),
    semester: Semester | None = None,
    event_scope: EventScope | None = None,
    organization_id: uuid.UUID | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    if period in {"school_year", "semester"} and school_year is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="school_year is required for school-year and semester reports",
        )
    if period == "semester" and semester is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="semester is required for semester reports",
        )

    start_date = end_date = None
    if school_year is not None:
        try:
            validate_school_year(school_year)
        except ValueError as exc:
            raise HTTPException(422, str(exc))
    if period in {"weekly", "monthly"}:
        start_date, end_date = _calendar_window(period, reference_date or institution_today())

    event_query = for_organization(scope_query_by_department(
        db.query(Event), Event.department_id, current_user
    ), Event, organization_id)
    if school_year is not None:
        event_query = event_query.filter(Event.school_year == school_year)
    if semester is not None:
        event_query = event_query.filter(Event.semester == semester)
    if event_scope is not None:
        event_query = event_query.filter(Event.event_scope == event_scope)
    events = event_query.order_by(Event.title).all()
    event_ids = [event.id for event in events]

    income_by_event: dict[uuid.UUID, list[IncomeRecord]] = defaultdict(list)
    expenses_by_event: dict[uuid.UUID, list[Expense]] = defaultdict(list)
    if event_ids:
        income_query = db.query(IncomeRecord).options(selectinload(IncomeRecord.receipt)).filter(IncomeRecord.event_id.in_(event_ids))
        expense_query = db.query(Expense).filter(
            Expense.event_id.in_(event_ids),
            Expense.status == "approved",
        )
        expense_query = scope_query_by_department(expense_query, Expense.department_id, current_user)
        if start_date is not None and end_date is not None:
            income_query = income_query.filter(
                IncomeRecord.received_on >= start_date,
                IncomeRecord.received_on <= end_date,
            )
            expense_query = expense_query.filter(
                Expense.expense_date >= start_date,
                Expense.expense_date <= end_date,
            )
        for income in income_query.all():
            income_by_event[income.event_id].append(income)
        for expense in expense_query.all():
            expenses_by_event[expense.event_id].append(expense)

    event_summaries = []
    eligible_incomes = []
    withheld_incomes = []
    for event in events:
        event_incomes = income_by_event[event.id]
        event_expenses = expenses_by_event[event.id]
        withheld = [i for i in event_incomes if i.receipt_review_status in {"pending", "rejected"}]
        eligible = [i for i in event_incomes if i.receipt_review_status not in {"pending", "rejected"}]
        eligible_incomes.extend(eligible)
        withheld_incomes.extend(withheld)
        total_income = _sum_amounts(eligible)
        total_expenses = _sum_amounts(event_expenses)
        event_summaries.append(
            FinancialEventSummary(
                event_id=event.id,
                title=event.title,
                school_year=event.school_year,
                semester=event.semester,
                event_scope=event.event_scope,
                income_count=len(eligible),
                expense_count=len(event_expenses),
                total_income=total_income,
                total_expenses=total_expenses,
                net_balance=total_income - total_expenses,
                withheld_income_total=_sum_amounts(withheld),
                withheld_income_count=len(withheld),
            )
        )

    unassigned_expense_total = 0.0
    if (
        start_date is not None
        and end_date is not None
        and school_year is None
        and semester is None
        and event_scope is None
    ):
        unassigned_query = for_organization(scope_query_by_department(
            db.query(Expense), Expense.department_id, current_user
        ), Expense, organization_id)
        unassigned_expense_total = float(
            unassigned_query.with_entities(func.coalesce(func.sum(Expense.amount), 0))
            .filter(
                Expense.event_id.is_(None),
                Expense.status == "approved",
                Expense.expense_date >= start_date,
                Expense.expense_date <= end_date,
            )
            .scalar()
        )

    total_income = sum((Decimal(str(row.total_income)) for row in event_summaries), Decimal("0.00"))
    total_expenses = sum((Decimal(str(row.total_expenses)) for row in event_summaries), Decimal("0.00"))
    unassigned_expense_total = Decimal(str(unassigned_expense_total))
    return ConsolidatedFinancialReport(
        period=period,
        start_date=start_date,
        end_date=end_date,
        school_year=school_year,
        semester=semester,
        event_scope=event_scope,
        total_income=total_income,
        total_expenses=total_expenses + unassigned_expense_total,
        unassigned_expense_total=unassigned_expense_total,
        net_balance=total_income - total_expenses - unassigned_expense_total,
        events=event_summaries,
        income_by_source=_income_sources(eligible_incomes),
        withheld_income_total=_sum_amounts(withheld_incomes),
        withheld_income_count=len(withheld_incomes),
    )
