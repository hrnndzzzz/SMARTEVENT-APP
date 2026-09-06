"""
CRUD + approval workflow for event proposals.

Status flow (two-stage, matching the Flutter app's existing UX):
    draft --submit--> pending_adviser --approve--> pending_admin --approve--> approved
                            \--reject--> rejected         \--reject--> rejected
    ("completed" exists as a status value for later — once an approved
    event has actually happened — but nothing transitions an event to
    it yet. Add a POST /events/{id}/complete route when you get there,
    same shape as submit/approve.)

Whoever PROPOSES an event skips their own review stage — approving your
own proposal is redundant, and an admin has nothing above them in the
hierarchy to review it:
    - officer proposes  -> starts at pending_adviser (needs both stages)
    - adviser proposes  -> starts at pending_admin (adviser stage skipped)
    - admin proposes     -> auto-approved immediately (no review needed)

Access rules:
  - Anyone logged in can VIEW events (GET routes) — officers need to
    see what's proposed, advisers need the queue to review.
  - The officer (or admin) who proposed an event can edit it while it's
    still a draft OR rejected (editing a rejected event and resubmitting
    is how an officer fixes and retries a proposal — this restarts the
    approval chain via _initial_pending_status, same rule as above).
  - Only advisers can approve/reject events at the pending_adviser stage.
  - Only admins can approve/reject events at the pending_admin stage.
  - Every approve/reject writes a row to `approvals` instead of just
    flipping the status, so GET /events/{id}/approvals gives a full
    review timeline (who decided what, and when) rather than only the
    final outcome. Resubmission doesn't erase this history — a new
    submission just adds new approval rows with the next step_order,
    so the full back-and-forth (reject, edit, resubmit, approve) stays
    visible in the timeline.
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
    # Approval rows accumulate per event (across resubmissions too), so
    # each new approve/reject gets the next step number in that event's
    # full review timeline.
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


def _initial_pending_status(proposer_role: str) -> str:
    """
    Maps whoever is proposing/resubmitting an event to the correct
    starting stage, skipping their own review step.
    """
    if proposer_role == "adviser":
        return "pending_admin"
    if proposer_role == "admin":
        return "approved"
    return "pending_adviser"


@router.post("", response_model=EventOut, status_code=status.HTTP_201_CREATED)
def create_event(
    payload: EventCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # If the client is creating straight into review (not saving a
    # draft first), route it through the same creator-skip logic as
    # submit_event rather than a bare "pending".
    initial_status = payload.status
    if initial_status == "pending":
        initial_status = _initial_pending_status(current_user.role)

    event = Event(
        category_id=payload.category_id,
        title=payload.title,
        description=payload.description,
        proposed_by=current_user.id,
        status=initial_status,
        event_date=payload.event_date,
        estimated_cost=payload.estimated_cost,
        allocated_budget=payload.allocated_budget,
        # A brand-new event starts with its full allocation available —
        # remaining_budget only ever decreases from here via the
        # fn_deduct_event_budget trigger, same pattern as categories.
        remaining_budget=payload.allocated_budget,
    )
    db.add(event)
    db.commit()
    db.refresh(event)

    if event.status == "approved":
        _record_decision(db, event, "approved", current_user, "Auto-approved: proposed by admin.")
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

    if event.status not in ("draft", "rejected"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only draft or rejected events can be edited",
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
    """
    Moves a draft into review, OR resubmits a previously rejected event
    (the Flutter app's "Edit Proposal" -> "Save Changes" flow on a
    rejected event calls PATCH then this, in that order). Either way,
    the starting stage is chosen by _initial_pending_status based on
    who's doing the submitting right now — not who originally proposed
    it — so if an admin edits and resubmits someone else's rejected
    proposal, it correctly skips straight to approved.
    """
    event = _get_event_or_404(db, event_id)
    _assert_owner_or_admin(event, current_user, "submit")

    if event.status not in ("draft", "rejected"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Event is already '{event.status}' — only draft or rejected events can be submitted",
        )

    was_resubmission = event.status == "rejected"
    event.status = _initial_pending_status(current_user.role)

    if was_resubmission:
        _record_decision(
            db, event, "resubmitted", current_user,
            "Event revised and resubmitted for review.",
        )

    if event.status == "approved":
        _record_decision(db, event, "approved", current_user, "Auto-approved: submitted by admin.")

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

    if current_user.role == "adviser":
        if event.status != "pending_adviser":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Event is '{event.status}' — advisers can only act while it's pending adviser review",
            )
        _record_decision(db, event, "approved", current_user, payload.remarks)
        event.status = "pending_admin"

    else:  # admin
        if event.status != "pending_admin":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Event is '{event.status}' — admins can only give final approval while it's pending admin approval",
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

    if current_user.role == "adviser" and event.status != "pending_adviser":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Event is '{event.status}' — advisers can only act while it's pending adviser review",
        )
    if current_user.role == "admin" and event.status not in ("pending_adviser", "pending_admin"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Event is '{event.status}' — nothing pending to reject",
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
