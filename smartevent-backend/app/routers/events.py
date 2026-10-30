import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import (
    assert_not_self_review,
    assert_department_scope,
    assert_record_scope,
    assert_owner_or_admin,
    require_operational_read,
    require_event_proposer,
    require_role,
    resolve_organization_id,
    scope_query_by_department,
)
from app.models import Approval, Category, DocumentRouting, Event, EventParticipant, EventRequirement, RequirementPreset, User
from app.models_compliance import EventLogistics, EventPersonnel, EventVehicle, EventComplianceDocument
from app.models_sap import SAPProposal
from app.services.compliance import invalidate_clearance
from app.schemas import (
    ApprovalDecision,
    ApprovalOut,
    EventCreate,
    EventOut,
    EventUpdate,
    EventAcademicMetadata,
    DocumentRoutingOut,
    DocumentRoutingUpdate,
    RequirementPresetOut,
)
from app.services.academic_year import validate_school_year
from app.services.access_audit import record_access_change
from app.services.approvals import record_decision
from app.services.event_routing import (
    assert_event_read, begin_institutional_review, require_event_reader,
    restart_routing, review_institutional_step, routing_steps,
    scope_event_query, validate_signatories,
)

router = APIRouter(prefix="/events", tags=["events"])
ADVISER_PENDING_STATUSES = {"pending", "pending_adviser"}


def _require_academic_metadata(event):
    try:
        validate_school_year(event.school_year)
        if event.semester not in {"1st", "2nd", "summer"} or event.event_scope not in {"departmental", "organizational"}:
            raise ValueError("semester and event_scope are required")
    except ValueError as exc:
        raise HTTPException(409, f"Complete the event's academic metadata first: {exc}")


def _get_event_or_404(db: Session, event_id: uuid.UUID, *, lock: bool = False, allow_sap: bool = False) -> Event:
    query = db.query(Event).filter(Event.id == event_id)
    if lock:
        query = query.with_for_update()
    event = query.first()
    if event is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    if lock and not allow_sap:
        from app.services.sap import assert_generic_workflow
        assert_generic_workflow(db, event)
    return event


def _assert_event_owner_scope(event: Event, current_user: User, action: str) -> None:
    assert_owner_or_admin(event.proposed_by, current_user, action, owner_roles={"adviser", "treasurer", "officer"})
    assert_record_scope(current_user, event, allow_officer_read=True)


def _initial_pending_status(proposer_role: str) -> str:
    if proposer_role == "adviser":
        return "pending_admin"
    return "pending_adviser"


@router.post("", response_model=EventOut, status_code=status.HTTP_201_CREATED)
def create_event(
    payload: EventCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_event_proposer),
):
    initial_status = payload.status
    if initial_status == "pending":
        initial_status = _initial_pending_status(current_user.role)

    category = None
    if payload.category_id is not None:
        category = db.query(Category).filter(Category.id == payload.category_id).first()
        if category is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="category_id does not match any existing category")
        assert_record_scope(current_user, category, allow_officer_read=True)

    if current_user.role in {"adviser", "treasurer", "admin", "officer"}:
        department_id = current_user.department_id
        if payload.department_id is not None and payload.department_id != department_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only create events in your assigned department.",
            )
        assert_department_scope(current_user, department_id, allow_officer_read=True)
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
    current_user: User = Depends(require_event_reader),
):
    query = scope_event_query(db.query(Event), db, current_user)
    if school_year is not None:
        try:
            validate_school_year(school_year)
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        query = query.filter(Event.school_year == school_year)
    if missing_school_year:
        query = query.filter(Event.school_year.is_(None))
    return query.order_by(Event.created_at.desc()).all()


@router.get("/requirement-presets", response_model=list[RequirementPresetOut])
def list_requirement_presets(db: Session = Depends(get_db), current_user: User = Depends(require_operational_read)):
    return db.query(RequirementPreset).order_by(RequirementPreset.phase, RequirementPreset.name).all()


@router.get("/school-years", response_model=list[str])
def list_school_years(db: Session = Depends(get_db), current_user: User = Depends(require_operational_read)):
    query = scope_query_by_department(db.query(Event), Event.department_id, current_user)
    return [row[0] for row in query.with_entities(Event.school_year).filter(
        Event.school_year.is_not(None)).distinct().order_by(Event.school_year.desc()).all()]


@router.patch("/{event_id}/academic-metadata", response_model=EventOut)
def repair_academic_metadata(event_id: uuid.UUID, payload: EventAcademicMetadata,
                             db: Session = Depends(get_db),
                             current_user: User = Depends(require_role("admin"))):
    event = _get_event_or_404(db, event_id, lock=True)
    assert_record_scope(current_user, event)
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
    current_user: User = Depends(require_event_reader),
):
    event = _get_event_or_404(db, event_id)
    assert_event_read(db, event, current_user)
    return event


@router.get("/{event_id}/approvals", response_model=list[ApprovalOut])
def list_event_approvals(
    event_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_event_reader),
):
    event = _get_event_or_404(db, event_id)
    assert_event_read(db, event, current_user)
    return (
        db.query(Approval)
        .filter(Approval.entity_type == "event", Approval.entity_id == event_id)
        .order_by(Approval.step_order)
        .all()
    )


@router.get("/{event_id}/routing", response_model=list[DocumentRoutingOut])
def list_document_routing(event_id: uuid.UUID, db: Session = Depends(get_db),
                          current_user: User = Depends(require_event_reader)):
    event = _get_event_or_404(db, event_id)
    assert_event_read(db, event, current_user)
    return db.query(DocumentRouting).filter(DocumentRouting.event_id == event.id).order_by(
        DocumentRouting.review_round, DocumentRouting.step_order).all()


@router.put("/{event_id}/routing", response_model=list[DocumentRoutingOut])
def configure_document_routing(event_id: uuid.UUID, payload: DocumentRoutingUpdate,
                                db: Session = Depends(get_db),
                                current_user: User = Depends(require_role("admin"))):
    event = _get_event_or_404(db, event_id, lock=True)
    assert_record_scope(current_user, event)
    if event.status not in {"draft", "pending", "pending_adviser", "pending_admin"}:
        raise HTTPException(409, "Configure routing before institutional review; resubmit rejected events first")
    previous = routing_steps(db, event)
    if any(step.status != "pending" for step in previous):
        raise HTTPException(409, "Routing decisions cannot be overwritten")
    validate_signatories(db, event, payload.signatory_ids)
    before = [str(step.signatory_id) for step in previous]
    for step in previous:
        db.delete(step)
    db.flush()
    steps = [DocumentRouting(event_id=event.id, review_round=event.review_round,
        step_order=index, signatory_id=signatory_id)
        for index, signatory_id in enumerate(payload.signatory_ids, 1)]
    db.add_all(steps)
    record_access_change(db, current_user, "event.routing_configured", event, {
        "review_round": event.review_round, "before": before,
        "after": [str(value) for value in payload.signatory_ids],
    })
    db.commit()
    return routing_steps(db, event)


@router.patch("/{event_id}", response_model=EventOut)
def update_event(
    event_id: uuid.UUID,
    payload: EventUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_event_proposer),
):
    event = _get_event_or_404(db, event_id, lock=True)
    _assert_event_owner_scope(event, current_user, "edit")

    if event.status not in ("draft", "rejected"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only draft or rejected events can be edited",
        )

    updates = payload.model_dump(exclude_unset=True)
    if "allocated_budget" in updates:
        remaining = Decimal(str(event.remaining_budget)) + Decimal(str(updates["allocated_budget"])) - Decimal(str(event.allocated_budget))
        if remaining < 0:
            raise HTTPException(409, "Allocated budget cannot be less than the amount already spent")
        updates["remaining_budget"] = remaining
    if "department_id" in updates and updates["department_id"] != event.department_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins can change an event's department scope")
    category_id = updates.get("category_id", event.category_id)
    if category_id is not None:
        category = db.query(Category).filter(Category.id == category_id).first()
        if category is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="category_id does not match any existing category")
        assert_record_scope(current_user, category, allow_officer_read=True)
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

    if "event_date" in updates and updates["event_date"] != event.event_date:
        invalidate_clearance(db, event)
        record_access_change(db, current_user, "compliance.date_changed", event, {
            "previous_date": str(event.event_date), "new_date": str(updates["event_date"]),
            "clearance_invalidated": True,
        })
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
    current_user: User = Depends(require_event_proposer),
):
    event = _get_event_or_404(db, event_id, lock=True)
    _assert_event_owner_scope(event, current_user, "submit")

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
        restart_routing(db, event)
        record_decision(
            db, "event", event.id, "resubmitted", current_user,
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
    current_user: User = Depends(require_role("adviser", "admin", "signatory")),
):
    event = _get_event_or_404(db, event_id, lock=True, allow_sap=True)

    assert_event_read(db, event, current_user)
    assert_not_self_review(event.proposed_by, current_user)
    proposal = db.query(SAPProposal).filter_by(event_id=event.id).first()
    if proposal is not None:
        from app.services import sap
        sap.department_review(db, event, proposal, current_user, "approved", payload.remarks)
        db.refresh(event)
        return event
    _require_academic_metadata(event)

    if current_user.role == "signatory":
        review_institutional_step(db, event, current_user, "approved", payload.remarks)
    elif current_user.role == "adviser":
        if event.status not in ADVISER_PENDING_STATUSES:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Event is '{event.status}' — advisers can only act while it's pending adviser review",
            )
        record_decision(db, "event", event.id, "approved", current_user, payload.remarks)
        event.status = "pending_admin"

    else:
        if event.status != "pending_admin":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Event is '{event.status}' — admins can only review while it is pending admin approval",
            )
        begin_institutional_review(db, event)
        record_decision(db, "event", event.id, "approved", current_user, payload.remarks)

    db.commit()
    db.refresh(event)
    return event


@router.post("/{event_id}/reject", response_model=EventOut)
def reject_event(
    event_id: uuid.UUID,
    payload: ApprovalDecision = ApprovalDecision(),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("adviser", "admin", "signatory")),
):
    event = _get_event_or_404(db, event_id, lock=True, allow_sap=True)

    assert_event_read(db, event, current_user)
    assert_not_self_review(event.proposed_by, current_user)
    proposal = db.query(SAPProposal).filter_by(event_id=event.id).first()
    if proposal is not None:
        from app.services import sap
        sap.department_review(db, event, proposal, current_user, "returned", payload.remarks)
        db.refresh(event)
        return event

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

    if current_user.role == "signatory":
        review_institutional_step(db, event, current_user, "rejected", payload.remarks)
    else:
        record_decision(db, "event", event.id, "rejected", current_user, payload.remarks)
        event.status = "rejected"

    db.commit()
    db.refresh(event)
    return event


@router.delete("/{event_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_event(
    event_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_event_proposer),
):
    event = _get_event_or_404(db, event_id, lock=True)
    _assert_event_owner_scope(event, current_user, "delete")

    if event.status != "draft":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "Only draft events can be deleted. Submitted events must go "
                "through the approval flow (or stay rejected) instead."
            ),
        )

    if any(db.query(model).filter_by(event_id=event.id).first() for model in
           (EventParticipant, EventRequirement, EventPersonnel, EventVehicle, EventComplianceDocument)):
        raise HTTPException(409, "This draft has compliance records; retain it to preserve the paper trail")
    logistics = db.get(EventLogistics, event.id)
    if logistics:
        db.delete(logistics)
    for step in routing_steps(db, event):
        db.delete(step)
    try:
        db.flush()
        db.delete(event)
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(status_code=409, detail="This draft is referenced by other records and cannot be deleted") from exc
    return None
