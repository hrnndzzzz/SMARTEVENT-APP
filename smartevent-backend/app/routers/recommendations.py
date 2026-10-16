import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import (
    assert_record_scope,
    require_operational_read,
    scope_query_by_department,
)
from app.models import Category, Event, Expense, User
from app.schemas import BudgetRecommendation

router = APIRouter(prefix="/recommendations", tags=["recommendations"])

_MIN_SAMPLE_SIZE = 2


@router.get("/event-budget", response_model=BudgetRecommendation)
def recommend_event_budget(
    category_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")
    assert_record_scope(current_user, category, allow_officer_read=True)

    past_events = (
        scope_query_by_department(db.query(Event), Event.department_id, current_user)
        .filter(Event.category_id == category_id, Event.status.in_(["approved", "completed"]))
        .all()
    )

    sample_size = len(past_events)

    if sample_size < _MIN_SAMPLE_SIZE:
        return BudgetRecommendation(
            category_id=category_id,
            sample_size=sample_size,
            avg_allocated_budget=None,
            avg_actual_spend=None,
            note=(
                f"Only {sample_size} past approved/completed event(s) in this "
                f"category — need at least {_MIN_SAMPLE_SIZE} for a meaningful "
                f"recommendation. Showing no suggestion rather than a misleading one."
            ),
        )

    avg_allocated = sum(float(e.allocated_budget) for e in past_events) / sample_size

    event_ids = [e.id for e in past_events]
    expense_query = scope_query_by_department(
        db.query(Expense), Expense.department_id, current_user
    )
    per_event_spend = (
        expense_query.with_entities(Expense.event_id, func.coalesce(func.sum(Expense.amount), 0))
        .filter(Expense.event_id.in_(event_ids), Expense.status == "approved")
        .group_by(Expense.event_id)
        .all()
    )
    spend_by_event = {event_id: float(total) for event_id, total in per_event_spend}
    avg_actual_spend = (
        sum(spend_by_event.get(e.id, 0.0) for e in past_events) / sample_size
    )

    return BudgetRecommendation(
        category_id=category_id,
        sample_size=sample_size,
        avg_allocated_budget=round(avg_allocated, 2),
        avg_actual_spend=round(avg_actual_spend, 2),
        note=(
            f"Based on {sample_size} past approved/completed event(s) in "
            f"'{category.name}'. avg_allocated_budget is what those events "
            f"PLANNED to spend; avg_actual_spend is what they actually spent "
            f"— use whichever fits your planning style, or split the difference."
        ),
    )
