"""
GET /recommendations/event-budget — a data-driven starting point for
how much to allocate to a new event, based on past events sharing the
same budget category. This is the "Smart Recommendations engine" from
the capstone scope, at the level actually committed to for this
version: historical-average heuristics, not predictive ML — matching
the scope document's own note that AI-driven recommendations are a
future-iteration enhancement, not required for the current system.

Uses category_id (not a separate event_type field) — decided over
adding a new schema concept, since category_id already exists and is
set on every event.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import Category, Event, Expense, User
from app.schemas import BudgetRecommendation

router = APIRouter(prefix="/recommendations", tags=["recommendations"])

# Below this many past events in the category, an average is more
# misleading than useful — one wildly expensive or wildly cheap past
# event would completely dominate the "average."
_MIN_SAMPLE_SIZE = 2


@router.get("/event-budget", response_model=BudgetRecommendation)
def recommend_event_budget(
    category_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")

    # Only look at events that actually went somewhere (approved or
    # completed) — a draft or rejected event's allocated_budget was
    # never real money, so including it would skew the average toward
    # numbers that were proposed but never actually happened.
    past_events = (
        db.query(Event)
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
    per_event_spend = (
        db.query(Expense.event_id, func.coalesce(func.sum(Expense.amount), 0))
        .filter(Expense.event_id.in_(event_ids), Expense.status == "approved")
        .group_by(Expense.event_id)
        .all()
    )
    spend_by_event = {event_id: float(total) for event_id, total in per_event_spend}
    # Events with zero approved expenses aren't in spend_by_event at
    # all (no rows to group) — treat them as 0 spend, not "missing
    # data", so they still count toward the average.
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
