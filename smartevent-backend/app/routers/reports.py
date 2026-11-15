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
    CategorySpend,
    ConsolidatedFinancialReport,
    EventReport,
    EventScope,
    FinancialEventSummary,
    LedgerEntry,
    PeriodTotals,
    Semester,
    IncomeSourceSummary,
    TrendPoint,
)

router = APIRouter(prefix="/reports", tags=["reports"])

# Events whose budget is committed. Earlier stages are still proposals, so
# their allocations stay out of "budget used".
COMMITTED_STATUSES = {"approved", "completed"}
SEMESTER_ORDER = ["1st", "2nd", "summer"]


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


def _previous_period(period, reference, school_year, semester):
    """(reference date, school year, semester) of the period just before this one."""
    if period == "weekly":
        return reference - timedelta(days=7), school_year, semester
    if period == "monthly":
        return reference.replace(day=1) - timedelta(days=1), school_year, semester
    start = int(school_year[:4])
    earlier = f"{start - 1}-{start}"
    if period == "school_year":
        return reference, earlier, semester
    index = SEMESTER_ORDER.index(semester)
    return (reference, school_year, SEMESTER_ORDER[index - 1]) if index else (reference, earlier, "summer")


def _months_between(first: str, last: str) -> list[str]:
    year, month = map(int, first.split("-"))
    months = []
    while f"{year:04d}-{month:02d}" <= last:
        months.append(f"{year:04d}-{month:02d}")
        year, month = (year + 1, 1) if month == 12 else (year, month + 1)
    return months


def _trend(incomes, expenses, start_date, end_date):
    """Counted money per day (calendar periods) or per month (academic ones)."""
    daily = start_date is not None
    key = (lambda d: d.isoformat()) if daily else (lambda d: d.strftime("%Y-%m"))
    income, spent = defaultdict(Decimal), defaultdict(Decimal)
    for record in incomes:
        income[key(record.received_on)] += Decimal(str(record.amount))
    for record in expenses:
        spent[key(record.expense_date)] += Decimal(str(record.amount))
    if daily:
        buckets = [key(start_date + timedelta(days=n)) for n in range((end_date - start_date).days + 1)]
    else:
        present = sorted(set(income) | set(spent))
        buckets = _months_between(present[0], present[-1]) if present else []
    return [TrendPoint(bucket=b, total_income=income[b], total_expenses=spent[b]) for b in buckets]


def _financial_report(db, current_user, *, period, reference, school_year, semester,
                      event_scope, organization_id) -> ConsolidatedFinancialReport:
    start_date = end_date = None
    if period in {"weekly", "monthly"}:
        start_date, end_date = _calendar_window(period, reference)

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
    spent_to_date = {}
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
        spent_to_date = dict(
            scope_query_by_department(
                db.query(Expense.event_id, func.coalesce(func.sum(Expense.amount), 0)),
                Expense.department_id, current_user,
            )
            .filter(Expense.event_id.in_(event_ids), Expense.status == "approved")
            .group_by(Expense.event_id)
            .all()
        )

    event_summaries = []
    eligible_incomes = []
    withheld_incomes = []
    counted_expenses = []
    for event in events:
        event_incomes = income_by_event[event.id]
        event_expenses = expenses_by_event[event.id]
        withheld = [i for i in event_incomes if i.receipt_review_status in {"pending", "rejected"}]
        eligible = [i for i in event_incomes if i.receipt_review_status not in {"pending", "rejected"}]
        eligible_incomes.extend(eligible)
        withheld_incomes.extend(withheld)
        counted_expenses.extend(event_expenses)
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
                status=event.status,
                event_date=event.event_date,
                allocated_budget=float(event.allocated_budget or 0),
                spent_to_date=float(spent_to_date.get(event.id, 0)),
            )
        )

    # Spending tied to no event belongs to no academic label, so it only
    # appears in unfiltered calendar reports.
    unassigned = []
    if (
        start_date is not None
        and end_date is not None
        and school_year is None
        and semester is None
        and event_scope is None
    ):
        unassigned = (
            for_organization(scope_query_by_department(
                db.query(Expense), Expense.department_id, current_user
            ), Expense, organization_id)
            .filter(
                Expense.event_id.is_(None),
                Expense.status == "approved",
                Expense.expense_date >= start_date,
                Expense.expense_date <= end_date,
            )
            .all()
        )
    counted_expenses.extend(unassigned)

    category_ids = {expense.category_id for expense in counted_expenses}
    category_names = dict(
        db.query(Category.id, Category.name).filter(Category.id.in_(category_ids)).all()
    ) if category_ids else {}
    by_category = defaultdict(list)
    for expense in counted_expenses:
        by_category[expense.category_id].append(expense)
    expenses_by_category = sorted(
        (CategorySpend(category_id=category_id, category_name=category_names.get(category_id, "Uncategorised"),
                       expense_count=len(rows), total_expenses=_sum_amounts(rows))
         for category_id, rows in by_category.items()),
        key=lambda row: -row.total_expenses,
    )

    titles = {event.id: event.title for event in events}

    def income_row(income, counted):
        return LedgerEntry(
            occurred_on=income.received_on, kind="income", event_id=income.event_id,
            event_title=titles.get(income.event_id), label=income.source,
            source_type=income.source_type, description=income.purpose, amount=income.amount,
            counted=counted, flagged=bool(income.receipt and income.receipt.is_flagged),
        )

    ledger = [income_row(i, True) for i in eligible_incomes]
    ledger += [income_row(i, False) for i in withheld_incomes]
    ledger += [
        LedgerEntry(
            occurred_on=e.expense_date, kind="expense", event_id=e.event_id,
            event_title=titles.get(e.event_id), label=category_names.get(e.category_id, "Uncategorised"),
            description=e.description, amount=e.amount, flagged=bool(e.is_flagged),
        )
        for e in counted_expenses
    ]
    ledger.sort(key=lambda row: (row.occurred_on, row.kind), reverse=True)

    committed = [row for row in event_summaries if row.status in COMMITTED_STATUSES]
    total_income = _sum_amounts(eligible_incomes)
    total_expenses = _sum_amounts(counted_expenses)
    unassigned_expense_total = _sum_amounts(unassigned)
    return ConsolidatedFinancialReport(
        period=period,
        start_date=start_date,
        end_date=end_date,
        school_year=school_year,
        semester=semester,
        event_scope=event_scope,
        total_income=total_income,
        total_expenses=total_expenses,
        unassigned_expense_total=unassigned_expense_total,
        net_balance=total_income - total_expenses,
        events=event_summaries,
        income_by_source=_income_sources(eligible_incomes),
        withheld_income_total=_sum_amounts(withheld_incomes),
        withheld_income_count=len(withheld_incomes),
        total_allocated_budget=sum((Decimal(str(row.allocated_budget)) for row in committed), Decimal("0.00")),
        total_spent_to_date=sum((Decimal(str(row.spent_to_date)) for row in committed), Decimal("0.00")),
        expenses_by_category=expenses_by_category,
        trend=_trend(eligible_incomes, counted_expenses, start_date, end_date),
        ledger=ledger,
    )


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

    if school_year is not None:
        try:
            validate_school_year(school_year)
        except ValueError as exc:
            raise HTTPException(422, str(exc))

    reference = reference_date or institution_today()
    scope = dict(event_scope=event_scope, organization_id=organization_id)
    report = _financial_report(db, current_user, period=period, reference=reference,
                               school_year=school_year, semester=semester, **scope)
    earlier_reference, earlier_year, earlier_semester = _previous_period(period, reference, school_year, semester)
    earlier = _financial_report(db, current_user, period=period, reference=earlier_reference,
                                school_year=earlier_year, semester=earlier_semester, **scope)
    report.previous = PeriodTotals(
        start_date=earlier.start_date, end_date=earlier.end_date,
        school_year=earlier.school_year, semester=earlier.semester,
        total_income=earlier.total_income, total_expenses=earlier.total_expenses,
        net_balance=earlier.net_balance,
    )
    return report
