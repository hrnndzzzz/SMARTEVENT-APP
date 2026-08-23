"""
Read-only aggregate views over the data the other routers already
manage. Nothing here writes anything — every endpoint is a query,
built from the same tables (categories, events, expenses, inventory)
you already have full CRUD on elsewhere.

Access: any logged-in user can view. Same reasoning as categories/
events — these are aggregate summaries of data everyone can already
see individually via the other routers; nothing here exposes anything
a role couldn't already piece together by listing categories/events/
expenses themselves.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import Category, Event, Expense, Inventory, User
from app.schemas import DashboardSummary, ExpenseOut, SpendingTrendPoint

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/dashboard", response_model=DashboardSummary)
def get_dashboard(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    total_categories = db.query(Category).count()
    allocated_sum, remaining_sum = db.query(
        func.coalesce(func.sum(Category.allocated_budget), 0),
        func.coalesce(func.sum(Category.remaining_budget), 0),
    ).first()

    events_by_status = dict(
        db.query(Event.status, func.count(Event.id)).group_by(Event.status).all()
    )
    expenses_by_status = dict(
        db.query(Expense.status, func.count(Expense.id)).group_by(Expense.status).all()
    )

    flagged_expense_count = db.query(Expense).filter(Expense.is_flagged.is_(True)).count()
    low_stock_item_count = (
        db.query(Inventory).filter(Inventory.quantity <= Inventory.low_stock_threshold).count()
    )
    draft_inventory_count = db.query(Inventory).filter(Inventory.is_draft.is_(True)).count()

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
    months: int = 6,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Total APPROVED expense spending per calendar month, most recent
    `months` months (default 6). Only approved expenses count — a
    pending or rejected expense hasn't actually cost the org anything
    yet, so including it would overstate real spending.
    """
    month_expr = func.date_trunc("month", Expense.created_at)

    rows = (
        db.query(
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
        for row in reversed(rows)  # oldest-to-newest, natural chart order
    ]


@router.get("/threats", response_model=list[ExpenseOut])
def get_flagged_expenses(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Every expense currently flagged (is_flagged=True) — set by the OCR
    amount-mismatch check in POST /expenses/{id}/parse-receipt when the
    scanned receipt total disagrees with the entered amount. (Note:
    over-budget conditions are handled separately, by blocking approval
    outright with a 409 in approve_expense — they don't set is_flagged.)
    This is your Threat Analysis Engine's actual review surface: OCR
    mismatches an adviser/admin should look at before approving.
    """
    return (
        db.query(Expense)
        .filter(Expense.is_flagged.is_(True))
        .order_by(Expense.created_at.desc())
        .all()
    )
