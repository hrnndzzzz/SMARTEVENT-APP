"""
CRUD + approval workflow for event proposals.

Status flow (two-stage, matching the Flutter app's existing UX):
    draft --submit--> pending_adviser --approve--> pending_admin --approve--> approved
                            --reject--> rejected         --reject--> rejected
    ("completed" exists as a status value for later — once an approved
    event has actually happened — but nothing transitions an event to
    it yet. Add a POST /events/{id}/complete route when you get there,
    same shape as submit/approve.)

The original proposer's role determines the starting review stage:
    - treasurer proposes -> starts at pending_adviser (needs both stages)
    - adviser proposes  -> starts at pending_admin (adviser stage skipped)
    - admin/super administrator proposes -> starts at pending_adviser
No proposal is auto-approved. The proposer cannot approve or reject it.

Access rules:
  - Operational readers see only their assigned organization/department;
    Super Admin has global access. Officers have view-only access.
  - The treasurer/adviser who proposed an event, or an administrator, can edit it while it's
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
  - Record-level organization and department scope is checked on reads
    and approval actions.
"""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import (
    assert_not_self_review,
    assert_department_scope,
    assert_record_scope,
    assert_owner_or_admin,
    require_operational_read,
    require_role,
    resolve_organization_id,
    scope_query_by_department,
)
from app.models import Approval, Category, Event, User
from app.schemas import (
    ApprovalDecision,
    ApprovalOut,
    EventCreate,
    EventOut,
    EventUpdate,
    EventAcademicMetadata,
)
from app.services.academic_year import validate_school_year
from app.services.access_audit import record_access_change

router = APIRouter(prefix="/events", tags=["events"])
ADVISER_PENDING_STATUSES = {"pending", "pending_adviser"}


def _require_academic_metadata(event):
    try:
        validate_school_year(event.school_year)
        if event.semester not in {"1st", "2nd", "summer"} or event.event_scope not in {"departmental", "organizational"}:
            raise ValueError("semester and event_scope are required")
    except ValueError as exc:
        raise HTTPException(409, f"Complete the event's academic metadata first: {exc}")


def _get_event_or_404(db: Session, event_id: uuid.UUID) -> Event:
    event = db.query(Event).filter(Event.id == event_id).first()
    if event is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    return event


def _assert_event_owner_scope(event: Event, db: Session, current_user: User, action: str) -> None:
    assert_owner_or_admin(event.proposed_by, current_user, action)
    assert_record_scope(current_user, event)


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
    return "pending_adviser"


@router.post("", response_model=EventOut, status_code=status.HTTP_201_CREATED)
def create_event(
    payload: EventCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("treasurer", "adviser", "admin")),
):
    # If the client is creating straight into review (not saving a
    # draft first), route it through the same creator-skip logic as
    # submit_event rather than a bare "pending".
    initial_status = payload.status
    if initial_status == "pending":
        initial_status = _initial_pending_status(current_user.role)

    category = None
    if payload.category_id is not None:
        category = db.query(Category).filter(Category.id == payload.category_id).first()
        if category is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="category_id does not match any existing category")
        assert_record_scope(current_user, category)

    if current_user.role in {"adviser", "treasurer", "admin"}:
        department_id = current_user.department_id
        if payload.department_id is not None and payload.department_id != department_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only create events in your assigned department.",
            )
        assert_department_scope(current_user, department_id)
    else:
        department_id = payload.department_id or (category.department_id if category else None)

    if payload.event_scope == "departmental" and department_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Departmental events require department_id",
        )

    if (
        category is not None
        and category.department_id is not None
        and department_id is not None
        and category.department_id != department_id
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Event department must match the selected category department",
        )

    organization_id = resolve_organization_id(
        db, current_user, payload.organization_id or (category.organization_id if category else None), department_id
    )
    if category is not None and category.organization_id != organization_id:
        raise HTTPException(status_code=400, detail="Event and category must belong to the same organization")

    event = Event(
        organization_id=organization_id,
        department_id=department_id,
        category_id=payload.category_id,
        school_year=payload.school_year,
        semester=payload.semester,
        event_scope=payload.event_scope,
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

    return event


@router.get("", response_model=list[EventOut])
def list_events(
    school_year: str | None = None,
    missing_school_year: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    query = scope_query_by_department(db.query(Event), Event.department_id, current_user)
    if school_year is not None:
        try:
            validate_school_year(school_year)
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        query = query.filter(Event.school_year == school_year)
    if missing_school_year:
        query = query.filter(Event.school_year.is_(None))
    return query.order_by(Event.created_at.desc()).all()


@router.get("/school-years", response_model=list[str])
def list_school_years(db: Session = Depends(get_db), current_user: User = Depends(require_operational_read)):
    query = scope_query_by_department(db.query(Event), Event.department_id, current_user)
    return [row[0] for row in query.with_entities(Event.school_year).filter(
        Event.school_year.is_not(None)).distinct().order_by(Event.school_year.desc()).all()]


@router.patch("/{event_id}/academic-metadata", response_model=EventOut)
def repair_academic_metadata(event_id: uuid.UUID, payload: EventAcademicMetadata,
                             db: Session = Depends(get_db),
                             current_user: User = Depends(require_role("admin"))):
    event = _get_event_or_404(db, event_id)
    assert_record_scope(current_user, event)
    # This is a migration repair, not a way to rewrite submitted event history.
    if event.school_year is not None and event.semester is not None and event.event_scope is not None:
        raise HTTPException(409, "Academic metadata is already recorded; use draft editing for changes")
    updates = payload.model_dump()
    for field, value in updates.items():
        existing = getattr(event, field)
        if existing is not None and existing != value:
            raise HTTPException(409, "Repair cannot replace already recorded academic metadata")
    for field, value in updates.items():
        setattr(event, field, value)
    record_access_change(db, current_user, "event.academic_metadata_repaired", event)
    db.commit()
    db.refresh(event)
    return event


@router.get("/{event_id}", response_model=EventOut)
def get_event(
    event_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    event = _get_event_or_404(db, event_id)
    assert_record_scope(current_user, event, allow_officer_read=True)
    return event


@router.get("/{event_id}/approvals", response_model=list[ApprovalOut])
def list_event_approvals(
    event_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    event = _get_event_or_404(db, event_id)
    assert_record_scope(current_user, event, allow_officer_read=True)
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
    current_user: User = Depends(require_role("treasurer", "adviser", "admin")),
):
    event = _get_event_or_404(db, event_id)
    _assert_event_owner_scope(event, db, current_user, "edit")

    if event.status not in ("draft", "rejected"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only draft or rejected events can be edited",
        )

    updates = payload.model_dump(exclude_unset=True)
    if "department_id" in updates and updates["department_id"] != event.department_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins can change an event's department scope")
    category_id = updates.get("category_id", event.category_id)
    if category_id is not None:
        category = db.query(Category).filter(Category.id == category_id).first()
        if category is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="category_id does not match any existing category")
        assert_record_scope(current_user, category)
        target_department_id = updates.get("department_id", event.department_id)
        if category.organization_id != event.organization_id:
            raise HTTPException(status_code=400, detail="Event and category must share an organization")
        if (
            category.department_id is not None
            and target_department_id is not None
            and category.department_id != target_department_id
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Event department must match the selected category department",
            )

    target_department_id = updates.get("department_id", event.department_id)
    target_scope = updates.get("event_scope", event.event_scope)
    if target_scope == "departmental" and target_department_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Departmental events require department_id",
        )

    for field, value in updates.items():
        setattr(event, field, value)

    _require_academic_metadata(event)
    db.commit()
    db.refresh(event)
    return event


@router.post("/{event_id}/submit", response_model=EventOut)
def submit_event(
    event_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("treasurer", "adviser", "admin")),
):
    """
    Moves a draft into review, OR resubmits a previously rejected event
    (the Flutter app's "Edit Proposal" -> "Save Changes" flow on a
    rejected event calls PATCH then this, in that order). Either way,
    the starting stage is chosen from the original proposer's role.
    An administrator resubmitting another user's proposal cannot bypass
    independent review. Existing approval history is retained.
    """
    event = _get_event_or_404(db, event_id)
    _assert_event_owner_scope(event, db, current_user, "submit")

    if event.status not in ("draft", "rejected"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Event is already '{event.status}' — only draft or rejected events can be submitted",
        )

    was_resubmission = event.status == "rejected"
    _require_academic_metadata(event)
    proposer = db.get(User, event.proposed_by)
    event.status = _initial_pending_status(proposer.role if proposer else "treasurer")

    if was_resubmission:
        _record_decision(
            db, event, "resubmitted", current_user,
            "Event revised and resubmitted for review.",
        )

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

    assert_record_scope(current_user, event)
    assert_not_self_review(event.proposed_by, current_user)
    _require_academic_metadata(event)

    if current_user.role == "adviser":
        if event.status not in ADVISER_PENDING_STATUSES:
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

    assert_record_scope(current_user, event)
    assert_not_self_review(event.proposed_by, current_user)

    if current_user.role == "adviser" and event.status not in ADVISER_PENDING_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Event is '{event.status}' — advisers can only act while it's pending adviser review",
        )
    if current_user.role in {"admin", "super_admin"} and event.status not in ADVISER_PENDING_STATUSES | {"pending_admin"}:
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
    current_user: User = Depends(require_role("treasurer", "adviser", "admin")),
):
    event = _get_event_or_404(db, event_id)
    _assert_event_owner_scope(event, db, current_user, "delete")

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
