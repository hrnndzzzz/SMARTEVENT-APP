"""Staff-managed participant paper trail and pre-activity evidence."""

import uuid
from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_role
from app.models import Event, EventParticipant, EventRequirement, RequirementPreset, StudentComplianceRecord, User
from app.models_compliance import EventComplianceDocument, EventLogistics, EventPersonnel, EventVehicle
from app.schemas_compliance import (
    ActiveUpdate, BatchReview, ComplianceRecordOut, DocumentReview, LogisticsUpdate,
    ParticipantCreate, ParticipantOut, ParticipantUpdate, PersonnelCreate,
    RequirementCreate, RequirementRequiredUpdate, VehicleCreate,
)
from app.services.access_audit import record_access_change
from app.services.compliance import (
    DEFAULT_PRESETS, EVENT_DOCUMENTS, THIRD_PARTY_DOCUMENTS, VEHICLE_DOCUMENTS,
    add_default_requirements, event_for_compliance, event_record, file_access,
    readiness, replace_submission, store_document, sync_compliance_records, invalidate_clearance,
)
from app.services.event_routing import assert_event_read, require_event_reader
from app.services.closure import review_student_records

router = APIRouter(prefix="/events/{event_id}", tags=["pre-activity compliance"])
staff = require_role("admin", "adviser")
proposer = require_role("admin", "adviser", "treasurer")


def save(db, event, user, action, details=None):
    db.flush()
    record_access_change(db, user, "compliance." + action, event, details)
    db.commit()


def public_row(row, fields):
    return {field: getattr(row, field) for field in fields.split()}


def document_out(row):
    return public_row(row, "id event_id vehicle_id kind reference_number valid_until validity_confirmed status version submitted_at reviewed_at reviewed_by remarks")


def student_record_out(row):
    return {**ComplianceRecordOut.model_validate(row).model_dump(), "has_document": bool(row.document_url)}


@router.get("/readiness")
def get_readiness(event_id: uuid.UUID, db: Session = Depends(get_db), user: User = Depends(require_event_reader)):
    event = db.get(Event, event_id)
    if event is None:
        raise HTTPException(404, "Event not found")
    assert_event_read(db, event, user)
    return readiness(db, event)


@router.get("/logistics")
def get_logistics(event_id: uuid.UUID, db: Session = Depends(get_db), user: User = Depends(require_role("admin", "adviser", "treasurer", "signatory"))):
    event = db.get(Event, event_id)
    if event is None:
        raise HTTPException(404, "Event not found")
    assert_event_read(db, event, user)
    logistics = db.get(EventLogistics, event.id)
    # This view intentionally contains no student names, medical records or email addresses.
    return {"logistics": public_row(logistics, "activity_location destination transport_mode transport_notes") if logistics else None,
        "personnel": [public_row(row, "id staff_reference full_name position qualifications is_active") for row in db.query(EventPersonnel).filter_by(event_id=event.id)],
        "vehicles": [public_row(row, "id plate_number operator_name driver_name out_of_line is_active") for row in db.query(EventVehicle).filter_by(event_id=event.id)],
        "documents": [document_out(row) for row in db.query(EventComplianceDocument).filter(
            EventComplianceDocument.event_id == event.id,
            EventComplianceDocument.kind.in_(EVENT_DOCUMENTS | VEHICLE_DOCUMENTS | THIRD_PARTY_DOCUMENTS | {"ltfrb_special_permit"}))]}


@router.put("/logistics")
def put_logistics(event_id: uuid.UUID, payload: LogisticsUpdate, db: Session = Depends(get_db), user: User = Depends(proposer)):
    event = event_for_compliance(db, event_id, user, write=True, structure=True, owner=True)
    if payload.activity_location == "on_campus" and payload.transport_mode != "none":
        raise HTTPException(422, "On-campus activities must use transport mode none")
    logistics = db.get(EventLogistics, event.id)
    if logistics is None:
        logistics = EventLogistics(event_id=event.id)
        db.add(logistics)
    elif any(getattr(logistics, key) != getattr(payload, key) for key in ("activity_location", "destination", "transport_mode")):
        invalidate_clearance(db, event)
    for key, value in payload.model_dump().items():
        setattr(logistics, key, value)
    if payload.activity_location == "off_campus":
        add_default_requirements(db, event)
    save(db, event, user, "logistics_updated", payload.model_dump())
    return get_logistics(event_id, db, user)


@router.get("/compliance")
def get_compliance(event_id: uuid.UUID, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = event_for_compliance(db, event_id, user)
    return {"participants": [ParticipantOut.model_validate(row) for row in db.query(EventParticipant).filter_by(event_id=event.id).order_by(EventParticipant.student_number)],
        "requirements": [public_row(row, "id preset_id name description phase is_required requires_notarization is_sensitive") for row in db.query(EventRequirement).filter_by(event_id=event.id)],
        "records": [student_record_out(row) for row in db.query(StudentComplianceRecord).filter_by(event_id=event.id)]}


@router.post("/participants", response_model=list[ParticipantOut], status_code=201)
def add_participants(event_id: uuid.UUID, payload: list[ParticipantCreate], db: Session = Depends(get_db), user: User = Depends(require_role("admin"))):
    event = event_for_compliance(db, event_id, user, write=True, structure=True)
    if not 1 <= len(payload) <= 500 or len({row.student_number for row in payload}) != len(payload):
        raise HTTPException(422, "Provide 1–500 students with distinct student numbers")
    rows = [EventParticipant(event_id=event.id, **row.model_dump()) for row in payload]
    db.add_all(rows)
    db.flush()
    sync_compliance_records(db, event)
    save(db, event, user, "participants_added", {"participant_ids": [str(row.id) for row in rows]})
    return rows


@router.patch("/participants/{participant_id}", response_model=ParticipantOut)
def update_participant(event_id: uuid.UUID, participant_id: uuid.UUID, payload: ParticipantUpdate,
                       db: Session = Depends(get_db), user: User = Depends(require_role("admin"))):
    event = event_for_compliance(db, event_id, user, write=True, structure=True)
    row = event_record(db, EventParticipant, event, participant_id)
    if row.full_name != payload.full_name and db.query(StudentComplianceRecord).filter(
        StudentComplianceRecord.participant_id == row.id,
        StudentComplianceRecord.status != "MISSING",
    ).first():
        raise HTTPException(409, "This student already has evidence. Withdraw an incorrect roster entry instead of changing its identity")
    for key, value in payload.model_dump().items():
        setattr(row, key, value)
    db.flush()
    sync_compliance_records(db, event)
    save(db, event, user, "participant_updated", {"participant_id": str(row.id), "active": row.is_active})
    return row


@router.post("/requirements", status_code=201)
def add_requirement(event_id: uuid.UUID, payload: RequirementCreate, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = event_for_compliance(db, event_id, user, write=True, structure=True)
    values = payload.model_dump()
    if payload.preset_id:
        preset = db.get(RequirementPreset, payload.preset_id)
        if preset is None or preset.phase != "pre_activity":
            raise HTTPException(422, "Choose a pre-activity preset; post-activity submissions belong to Phase 3")
        values.update(name=preset.name, description=preset.description,
                      requires_notarization=preset.requires_notarization, is_sensitive=preset.is_sensitive)
    row = EventRequirement(event_id=event.id, phase="pre_activity", **values)
    db.add(row)
    db.flush()
    sync_compliance_records(db, event)
    save(db, event, user, "requirement_added", {"requirement_id": str(row.id)})
    return public_row(row, "id name phase is_required requires_notarization is_sensitive")


@router.patch("/requirements/{requirement_id}")
def update_requirement(event_id: uuid.UUID, requirement_id: uuid.UUID, payload: RequirementRequiredUpdate,
                       db: Session = Depends(get_db), user: User = Depends(staff)):
    event = event_for_compliance(db, event_id, user, write=True, structure=True)
    row = event_record(db, EventRequirement, event, requirement_id)
    logistics = db.get(EventLogistics, event.id)
    preset = db.get(RequirementPreset, row.preset_id) if row.preset_id else None
    if logistics and logistics.activity_location == "off_campus" and preset and preset.code in DEFAULT_PRESETS and not payload.is_required:
        raise HTTPException(409, "Consent and medical clearance cannot be disabled for off-campus events")
    row.is_required = payload.is_required
    save(db, event, user, "requirement_updated", {"requirement_id": str(row.id), "is_required": row.is_required})
    return {"id": row.id, "is_required": row.is_required}


@router.post("/personnel", status_code=201)
def add_personnel(event_id: uuid.UUID, payload: PersonnelCreate, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = event_for_compliance(db, event_id, user, write=True, structure=True)
    row = EventPersonnel(event_id=event.id, **payload.model_dump(exclude={"institution_employee_confirmed"}))
    db.add(row)
    db.flush()
    save(db, event, user, "pic_assigned", {"personnel_id": str(row.id), "institution_employee_confirmed": True})
    return public_row(row, "id staff_reference full_name position qualifications is_active")


@router.patch("/personnel/{personnel_id}")
def set_personnel_active(event_id: uuid.UUID, personnel_id: uuid.UUID, payload: ActiveUpdate,
                         db: Session = Depends(get_db), user: User = Depends(staff)):
    event = event_for_compliance(db, event_id, user, write=True, structure=True)
    row = event_record(db, EventPersonnel, event, personnel_id)
    row.is_active = payload.is_active
    save(db, event, user, "pic_active_changed", {"personnel_id": str(row.id), "is_active": row.is_active})
    return {"id": row.id, "is_active": row.is_active}


@router.post("/vehicles", status_code=201)
def add_vehicle(event_id: uuid.UUID, payload: VehicleCreate, db: Session = Depends(get_db), user: User = Depends(proposer)):
    event = event_for_compliance(db, event_id, user, write=True, structure=True, owner=True)
    row = EventVehicle(event_id=event.id, **payload.model_dump())
    db.add(row)
    db.flush()
    save(db, event, user, "vehicle_added", {"vehicle_id": str(row.id)})
    return public_row(row, "id plate_number operator_name driver_name out_of_line is_active")


@router.patch("/vehicles/{vehicle_id}")
def set_vehicle_active(event_id: uuid.UUID, vehicle_id: uuid.UUID, payload: ActiveUpdate,
                       db: Session = Depends(get_db), user: User = Depends(proposer)):
    event = event_for_compliance(db, event_id, user, write=True, structure=True, owner=True)
    row = event_record(db, EventVehicle, event, vehicle_id)
    row.is_active = payload.is_active
    save(db, event, user, "vehicle_active_changed", {"vehicle_id": str(row.id), "is_active": row.is_active})
    return {"id": row.id, "is_active": row.is_active}


@router.post("/compliance/{record_id}/upload")
async def upload_student_document(event_id: uuid.UUID, record_id: uuid.UUID,
                                  version: int = Form(ge=1), file: UploadFile = File(...),
                                  db: Session = Depends(get_db), user: User = Depends(staff)):
    event = event_for_compliance(db, event_id, user, write=True)
    row = event_record(db, StudentComplianceRecord, event, record_id)
    participant = db.get(EventParticipant, row.participant_id)
    requirement = db.get(EventRequirement, row.requirement_id)
    if not participant.is_active or participant.participation_mode != "attending" or requirement.phase != "pre_activity" or row.version != version:
        raise HTTPException(409, "Refresh the active participant's pre-activity record before uploading")
    reference = await store_document(file, user.id, event.organization_id)
    previous = row.document_url
    replace_submission(row, reference, user.id)
    save(db, event, user, "student_document_uploaded", {"record_id": str(row.id), "version": row.version, "previous_reference": previous})
    return student_record_out(row)


@router.post("/compliance/batch-review")
def batch_review(event_id: uuid.UUID, payload: BatchReview, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = event_for_compliance(db, event_id, user, write=True)
    rows = review_student_records(db, event, user, payload, "pre_activity")
    save(db, event, user, "student_documents_reviewed", {
        "records": [{"id": str(row.id), "version": row.version} for row in rows],
        "decision": payload.decision, "evidence_mode": payload.evidence_mode,
        "notarization_confirmed": payload.notarization_confirmed, "remarks": payload.remarks})
    return [student_record_out(row) for row in rows]


@router.get("/compliance/{record_id}/file")
def student_document_file(event_id: uuid.UUID, record_id: uuid.UUID, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = event_for_compliance(db, event_id, user)
    row = event_record(db, StudentComplianceRecord, event, record_id)
    return file_access(row.document_url)


@router.post("/compliance-documents", status_code=201)
async def upload_event_document(event_id: uuid.UUID, kind: str = Form(...), reference_number: str = Form(min_length=1, max_length=150),
                                vehicle_id: uuid.UUID | None = Form(default=None), valid_until: date | None = Form(default=None),
                                version: int = Form(default=0, ge=0), file: UploadFile = File(...),
                                db: Session = Depends(get_db), user: User = Depends(proposer)):
    event = event_for_compliance(db, event_id, user, write=True, owner=True)
    reference_number = reference_number.strip()
    if not reference_number:
        raise HTTPException(422, "A document/correspondence reference is required")
    if vehicle_id:
        vehicle = event_record(db, EventVehicle, event, vehicle_id)
        if not vehicle.is_active or kind not in VEHICLE_DOCUMENTS | THIRD_PARTY_DOCUMENTS | {"ltfrb_special_permit"}:
            raise HTTPException(422, "Choose an active vehicle and a vehicle document type")
    elif kind not in EVENT_DOCUMENTS:
        raise HTTPException(422, "A vehicle is required for transport evidence")
    key = f"{vehicle_id or 'event'}:{kind}"
    row = db.query(EventComplianceDocument).filter_by(event_id=event.id, document_key=key).first()
    if (row.version if row else 0) != version:
        raise HTTPException(409, "The document changed; refresh before replacing it")
    reference = await store_document(file, user.id, event.organization_id)
    previous = row.document_url if row else None
    if row is None:
        row = EventComplianceDocument(event_id=event.id, vehicle_id=vehicle_id, kind=kind, document_key=key, version=0)
        db.add(row)
    row.document_url = reference
    row.reference_number = reference_number
    row.valid_until = valid_until
    row.validity_confirmed = False
    row.status = "SUBMITTED"
    row.submitted_by = user.id
    row.submitted_at = datetime.now(timezone.utc)
    row.reviewed_by = None
    row.reviewed_at = None
    row.remarks = None
    row.version += 1
    db.flush()
    save(db, event, user, "event_document_uploaded", {"document_id": str(row.id), "kind": row.kind, "version": row.version, "previous_reference": previous})
    return document_out(row)


@router.post("/compliance-documents/{document_id}/review")
def review_event_document(event_id: uuid.UUID, document_id: uuid.UUID, payload: DocumentReview,
                          db: Session = Depends(get_db), user: User = Depends(staff)):
    event = event_for_compliance(db, event_id, user, write=True)
    row = event_record(db, EventComplianceDocument, event, document_id)
    if row.version != payload.version or row.status != "SUBMITTED":
        raise HTTPException(409, "Review only the current submitted document version")
    if payload.decision == "VERIFIED" and row.vehicle_id:
        if not payload.validity_confirmed or event.event_date is None:
            raise HTTPException(422, "Confirm the transport document is valid for the scheduled event date")
        if row.valid_until and row.valid_until < event.event_date:
            raise HTTPException(422, "The document expires before the activity date")
    row.status = payload.decision
    row.validity_confirmed = payload.validity_confirmed if payload.decision == "VERIFIED" else False
    row.reviewed_by = user.id
    row.reviewed_at = datetime.now(timezone.utc)
    row.remarks = payload.remarks
    row.version += 1
    save(db, event, user, "event_document_reviewed", {"document_id": str(row.id), **payload.model_dump()})
    return document_out(row)


@router.get("/compliance-documents/{document_id}/file")
def event_document_file(event_id: uuid.UUID, document_id: uuid.UUID, db: Session = Depends(get_db), user: User = Depends(require_role("admin", "adviser", "treasurer", "signatory"))):
    event = db.get(Event, event_id)
    if event is None:
        raise HTTPException(404, "Event not found")
    assert_event_read(db, event, user)
    row = event_record(db, EventComplianceDocument, event, document_id)
    if row.kind in {"signed_attendance", "debriefing_report", "final_expense_report"} and user.role not in {"admin", "super_admin", "adviser"}:
        raise HTTPException(403, "Closure documents are available only to staff")
    return file_access(row.document_url)
