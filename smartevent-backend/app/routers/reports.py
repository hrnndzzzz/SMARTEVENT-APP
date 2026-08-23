"""
Consolidated, single-call financial reports — the "exportable
liquidation reports and expense breakdowns" from the capstone scope.
Each endpoint pulls together data that otherwise requires several
separate calls (category + its expenses, or event + its expenses) into
one response shaped for reading/printing as a report, not for further
API composition.

Access: any logged-in user can view, same reasoning as analytics.py.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import Category, Event, Expense, User
from app.schemas import CategoryReport, EventReport

router = APIRouter(prefix="/reports", tags=["reports"])


@router.get("/category/{category_id}", response_model=CategoryReport)
def get_category_report(
    category_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")

    total_spent = (
        db.query(func.coalesce(func.sum(Expense.amount), 0))
        .filter(Expense.category_id == category_id, Expense.status == "approved")
        .scalar()
    )

    counts = dict(
        db.query(Expense.status, func.count(Expense.id))
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
    current_user: User = Depends(get_current_user),
):
    event = db.query(Event).filter(Event.id == event_id).first()
    if event is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

    expenses = (
        db.query(Expense)
        .filter(Expense.event_id == event_id)
        .order_by(Expense.created_at)
        .all()
    )

    total_spent = sum(
        (float(expense.amount) for expense in expenses if expense.status == "approved"),
        0.0,
    )

    return EventReport(
        event_id=event.id,
        title=event.title,
        status=event.status,
        estimated_cost=float(event.estimated_cost),
        allocated_budget=float(event.allocated_budget),
        remaining_budget=float(event.remaining_budget),
        total_spent=total_spent,
        expenses=expenses,
    )
