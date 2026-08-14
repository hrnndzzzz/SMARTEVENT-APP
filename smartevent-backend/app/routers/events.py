"""
CRUD + approval workflow for event proposals.

Status flow:
    draft --submit--> pending --approve--> approved
                          \\--reject--> rejected
    ("completed" exists as a status value for later — once an approved
    event has actually happened — but nothing transitions an event to
    it yet. Add a POST /events/{id}/complete route when you get there,
    same shape as submit/approve.)

Access rules:
  - Anyone logged in can VIEW events (GET routes) — officers need to
    see what's proposed, advisers need the queue to review.
  - The officer (or admin) who proposed an event can edit, submit, or
    delete it while it's still a draft.
  - Only advisers/admins can approve or reject a submitted event.
  - Every approve/reject writes a row to `approvals` instead of just
    flipping the status, so GET /events/{id}/approvals gives a full
    review timeline (who decided what, and when) rather than only the
    final outcome.

Note: this doesn't stop an adviser from approving an event they also
proposed (self-review). If you want strict segregation of duties later,
that's a one-line check in approve_event/reject_event comparing
event.proposed_by to current_user.id.
"""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, require_role
from app.models import Approval, Event, User
from app.schemas import (
    ApprovalDecision,
    ApprovalOut,
    EventCreate,
    EventOut,
    EventUpdate,
)

router = APIRouter(prefix="/events", tags=["events"])


def _get_event_or_404(db: Session, event_id: uuid.UUID) -> Event:
    event = db.query(Event).filter(Event.id == event_id).first()
    if event is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    return event


def _assert_owner_or_admin(event: Event, current_user: User, action: str) -> None:
    if event.proposed_by != current_user.id and current_user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"You can only {action} events you proposed",
        )


def _next_step_order(db: Session, event_id: uuid.UUID) -> int:
    # Approval rows accumulate per event, so each new approve/reject
    # gets the next step number in that event's review timeline.
    count = (
        db.query(Approval)
        .filter(Approval.entity_type == "event", Approval.entity_id == event_id)
        .count()
    )
    return count + 1


def _record_decision(
    db: Session,
    event: Event,
    decision: str,
    reviewer: User,
    remarks: str | None,
) -> None:
    approval = Approval(
        entity_type="event",
        entity_id=event.id,
        step_order=_next_step_order(db, event.id),
        reviewer_id=reviewer.id,
        decision=decision,
        remarks=remarks,
        decided_at=datetime.now(timezone.utc),
    )
    db.add(approval)


@router.post("", response_model=EventOut, status_code=status.HTTP_201_CREATED)
def create_event(
    payload: EventCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = Event(
        category_id=payload.category_id,
        title=payload.title,
        description=payload.description,
        proposed_by=current_user.id,
        status=payload.status,
        event_date=payload.event_date,
        estimated_cost=payload.estimated_cost,
    )
    db.add(event)
    db.commit()
    db.refresh(event)
    return event


@router.get("", response_model=list[EventOut])
def list_events(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return db.query(Event).order_by(Event.created_at.desc()).all()


@router.get("/{event_id}", response_model=EventOut)
def get_event(
    event_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_event_or_404(db, event_id)


@router.get("/{event_id}/approvals", response_model=list[ApprovalOut])
def list_event_approvals(
    event_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _get_event_or_404(db, event_id)  # 404 if the event itself doesn't exist
    return (
        db.query(Approval)
        .filter(Approval.entity_type == "event", Approval.entity_id == event_id)
        .order_by(Approval.step_order)
        .all()
    )


@router.patch("/{event_id}", response_model=EventOut)
def update_event(
    event_id: uuid.UUID,
    payload: EventUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _get_event_or_404(db, event_id)
    _assert_owner_or_admin(event, current_user, "edit")

    if event.status != "draft":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only draft events can be edited",
        )

    updates = payload.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(event, field, value)

    db.commit()
    db.refresh(event)
    return event


@router.post("/{event_id}/submit", response_model=EventOut)
def submit_event(
    event_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _get_event_or_404(db, event_id)
    _assert_owner_or_admin(event, current_user, "submit")

    if event.status != "draft":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Event is already '{event.status}' — only drafts can be submitted",
        )

    event.status = "pending"
    db.commit()
    db.refresh(event)
    return event


@router.post("/{event_id}/approve", response_model=EventOut)
def approve_event(
    event_id: uuid.UUID,
    payload: ApprovalDecision = ApprovalDecision(),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("adviser", "admin")),
):
    event = _get_event_or_404(db, event_id)

    if event.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Event is '{event.status}' — only pending events can be approved",
        )

    _record_decision(db, event, "approved", current_user, payload.remarks)
    event.status = "approved"
    db.commit()
    db.refresh(event)
    return event


@router.post("/{event_id}/reject", response_model=EventOut)
def reject_event(
    event_id: uuid.UUID,
    payload: ApprovalDecision = ApprovalDecision(),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("adviser", "admin")),
):
    event = _get_event_or_404(db, event_id)

    if event.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Event is '{event.status}' — only pending events can be rejected",
        )

    _record_decision(db, event, "rejected", current_user, payload.remarks)
    event.status = "rejected"
    db.commit()
    db.refresh(event)
    return event


@router.delete("/{event_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_event(
    event_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = _get_event_or_404(db, event_id)
    _assert_owner_or_admin(event, current_user, "delete")

    if event.status != "draft":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "Only draft events can be deleted. Submitted events must go "
                "through the approval flow (or stay rejected) instead."
            ),
        )

    db.delete(event)
    db.commit()
    return None
