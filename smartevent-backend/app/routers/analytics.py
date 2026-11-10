import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_operational_read, require_role, scope_query_by_department
from app.models import Category, Event, Expense, Inventory, User
from app.schemas import DashboardSummary, ExpenseOut, SpendingTrendPoint

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/dashboard/exports")
def dashboard_exports(current_user: User = Depends(require_operational_read)):
    """Relative URLs: fetch with Authorization, then save/print response bytes."""
    return {
        "formats": {"pdf": "application/pdf", "csv": "text/csv", "html": "text/html"},
        "dashboard": {fmt: f"/reports/dashboard/export?format={fmt}" for fmt in ("pdf", "csv", "html")},
        "event_url_template": "/reports/event/{event_id}/export?format={format}",
        "category_url_template": "/reports/category/{category_id}/export?format={format}",
        "financial_url_template": "/reports/financial/export?period={period}&format={format}",
        "financial_filters": ["reference_date", "school_year", "semester", "event_scope", "organization_id"],
        "authorization": "Bearer token required on every export request; do not put tokens in URLs",
    }


def for_organization(query, model, organization_id: uuid.UUID | None):
    """Narrow an already-scoped query; an organization outside the caller's scope yields nothing."""
    return query if organization_id is None else query.filter(model.organization_id == organization_id)


@router.get("/dashboard", response_model=DashboardSummary)
def get_dashboard(
    organization_id: uuid.UUID | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    def scoped(model):
        query = scope_query_by_department(db.query(model), model.department_id, current_user)
        return for_organization(query, model, organization_id)

    category_query = scoped(Category)
    event_query = scoped(Event)
    expense_query = scoped(Expense)

    total_categories = category_query.count()
    allocated_sum, remaining_sum = category_query.with_entities(
        func.coalesce(func.sum(Category.allocated_budget), 0),
        func.coalesce(func.sum(Category.remaining_budget), 0),
    ).first()

    events_by_status = dict(
        event_query.with_entities(Event.status, func.count(Event.id)).group_by(Event.status).all()
    )
    expenses_by_status = dict(
        expense_query.with_entities(Expense.status, func.count(Expense.id)).group_by(Expense.status).all()
    )

    flagged_expense_count = expense_query.filter(Expense.is_flagged.is_(True)).count()
    inventory_query = scoped(Inventory).filter(Inventory.is_archived.is_(False))
    low_stock_item_count = inventory_query.filter(
        Inventory.quantity <= Inventory.low_stock_threshold
    ).count()
    draft_inventory_count = inventory_query.filter(Inventory.is_draft.is_(True)).count()

    return DashboardSummary(
        total_categories=total_categories,
        total_allocated_budget=float(allocated_sum),
        total_remaining_budget=float(remaining_sum),
        events_by_status=events_by_status,
        expenses_by_status=expenses_by_status,
        flagged_expense_count=flagged_expense_count,
        low_stock_item_count=low_stock_item_count,
        draft_inventory_count=draft_inventory_count,
    )


@router.get("/spending-trends", response_model=list[SpendingTrendPoint])
def get_spending_trends(
    months: int = Query(6, ge=1, le=120),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    month_expr = func.date_trunc("month", Expense.created_at)

    expense_query = scope_query_by_department(
        db.query(Expense), Expense.department_id, current_user
    )
    rows = (
        expense_query.with_entities(
            month_expr.label("month"),
            func.coalesce(func.sum(Expense.amount), 0).label("total"),
            func.count(Expense.id).label("count"),
        )
        .filter(Expense.status == "approved")
        .group_by(month_expr)
        .order_by(month_expr.desc())
        .limit(months)
        .all()
    )

    return [
        SpendingTrendPoint(
            month=row.month.strftime("%Y-%m"),
            total_amount=float(row.total),
            expense_count=row.count,
        )
        for row in reversed(rows)
    ]


@router.get("/threats", response_model=list[ExpenseOut])
def get_flagged_expenses(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("adviser", "treasurer", "officer", "admin")),
):
    query = scope_query_by_department(
        db.query(Expense), Expense.department_id, current_user
    )
    return (
        query
        .filter(Expense.is_flagged.is_(True))
        .order_by(Expense.created_at.desc())
        .all()
    )
