"""Attendance PDFs and staff-managed post-activity closure; no student login."""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import EventParticipant, EventRequirement, Organization, RequirementPreset, StudentComplianceRecord, User
from app.models_compliance import EventComplianceDocument, EventLogistics, EventParallelActivity
from app.routers.compliance import document_out, public_row, save, staff, student_record_out
from app.schemas import EventOut
from app.schemas_closure import EventCompletion, ParallelAssignment, ParticipationUpdate
from app.schemas_compliance import BatchReview, DocumentReview, RequirementCreate
from app.services.attendance_pdf import render_attendance
from app.services.closure import REPORT_KINDS, closeout_readiness, ensure_post_requirements, institution_today, review_student_records, scoped_event
from app.services.compliance import event_record, file_access, replace_submission, store_document, sync_compliance_records

router = APIRouter(prefix="/events/{event_id}", tags=["attendance and post-activity"])


@router.get("/attendance.pdf")
def attendance_pdf(event_id: uuid.UUID, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user, states={"approved", "completed"})
    participants = db.query(EventParticipant).filter_by(event_id=event.id, is_active=True, participation_mode="attending").order_by(EventParticipant.full_name, EventParticipant.student_number).all()
    if not participants:
        raise HTTPException(409, "Add an active participating roster before generating attendance")
    logistics = db.get(EventLogistics, event.id)
    organization = db.get(Organization, event.organization_id) if event.organization_id else None
    content = render_attendance(event, organization.name if organization else None,
        logistics.destination if logistics else None, participants)
    return Response(content, media_type="application/pdf", headers={
        "Content-Disposition": f'attachment; filename="attendance-{event.id}.pdf"', "Cache-Control": "no-store"})


@router.post("/complete", response_model=EventOut)
def complete_event(event_id: uuid.UUID, payload: EventCompletion, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user, write=True, states={"approved"})
    if event.event_date is None or payload.completed_on < event.event_date or payload.completed_on > institution_today():
        raise HTTPException(422, "Completion must be on/after the activity date and not in the future")
    ensure_post_requirements(db, event)
    event.status = "completed"
    event.completed_on = payload.completed_on
    event.completed_at = datetime.now(timezone.utc)
    event.completed_by = user.id
    save(db, event, user, "event_completed", {"completed_on": str(payload.completed_on), "remarks": payload.remarks})
    return event


@router.get("/post-activity")
def get_post_activity(event_id: uuid.UUID, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user)
    return {"readiness": closeout_readiness(db, event),
        "documents": [document_out(row) for row in db.query(EventComplianceDocument).filter(
            EventComplianceDocument.event_id == event.id, EventComplianceDocument.kind.in_(REPORT_KINDS))],
        "parallel_activities": [parallel_out(row) for row in db.query(EventParallelActivity).filter_by(event_id=event.id)]}


@router.post("/post-activity/requirements", status_code=201)
def add_post_requirement(event_id: uuid.UUID, payload: RequirementCreate, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user, write=True, states={"completed"})
    values = payload.model_dump()
    if payload.preset_id:
        preset = db.get(RequirementPreset, payload.preset_id)
        if preset is None or preset.phase != "post_activity":
            raise HTTPException(422, "Select a post-activity preset")
        values.update(name=preset.name, description=preset.description, requires_notarization=preset.requires_notarization, is_sensitive=preset.is_sensitive)
    row = EventRequirement(event_id=event.id, phase="post_activity", **values)
    db.add(row)
    db.flush()
    sync_compliance_records(db, event, "post_activity")
    save(db, event, user, "post_requirement_added", {"requirement_id": str(row.id)})
    return public_row(row, "id name phase is_required requires_notarization is_sensitive")


@router.post("/post-activity/initialize")
def initialize_post_activity(event_id: uuid.UUID, db: Session = Depends(get_db), user: User = Depends(staff)):
    # Supports historical completed events without rewriting their status or approvals.
    event = scoped_event(db, event_id, user, write=True, states={"completed"})
    ensure_post_requirements(db, event)
    save(db, event, user, "post_requirements_initialized")
    return get_post_activity(event_id, db, user)


@router.post("/post-activity/compliance/{record_id}/upload")
async def upload_post_student_document(event_id: uuid.UUID, record_id: uuid.UUID, version: int = Form(ge=1), file: UploadFile = File(...),
                                      db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user, write=True, states={"completed"})
    row = event_record(db, StudentComplianceRecord, event, record_id)
    participant = db.get(EventParticipant, row.participant_id)
    requirement = db.get(EventRequirement, row.requirement_id)
    if row.version != version or not participant.is_active or participant.participation_mode != "attending" or requirement.phase != "post_activity":
        raise HTTPException(409, "Refresh the active participant's post-activity record")
    reference = await store_document(file, user.id, event.organization_id)
    previous = row.document_url
    replace_submission(row, reference, user.id)
    save(db, event, user, "post_student_document_uploaded", {"record_id": str(row.id), "version": row.version, "previous_reference": previous})
    return student_record_out(row)


@router.post("/post-activity/compliance/batch-review")
def review_post_student_documents(event_id: uuid.UUID, payload: BatchReview, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user, write=True, states={"completed"})
    rows = review_student_records(db, event, user, payload, "post_activity")
    save(db, event, user, "post_student_documents_reviewed", {
        "records": [{"id": str(row.id), "version": row.version} for row in rows],
        "decision": payload.decision, "evidence_mode": payload.evidence_mode, "remarks": payload.remarks})
    return [student_record_out(row) for row in rows]


@router.post("/post-activity/documents", status_code=201)
async def upload_closure_document(event_id: uuid.UUID, kind: str = Form(...), reference_number: str = Form(min_length=1, max_length=150),
                                  version: int = Form(default=0, ge=0), file: UploadFile = File(...),
                                  db: Session = Depends(get_db), user: User = Depends(staff)):
    if kind not in REPORT_KINDS or not reference_number.strip():
        raise HTTPException(422, "Select a signed attendance, debriefing/assessment or final expense report and provide its reference")
    event = scoped_event(db, event_id, user, write=True, states={"approved", "completed"} if kind == "signed_attendance" else {"completed"})
    key = "event:" + kind
    row = db.query(EventComplianceDocument).filter_by(event_id=event.id, document_key=key).first()
    if (row.version if row else 0) != version:
        raise HTTPException(409, "The document changed; refresh before replacing it")
    reference = await store_document(file, user.id, event.organization_id)
    previous = row.document_url if row else None
    if row is None:
        row = EventComplianceDocument(event_id=event.id, kind=kind, document_key=key, version=0)
        db.add(row)
    row.document_url = reference
    row.reference_number = reference_number.strip()
    row.status = "SUBMITTED"
    row.submitted_by = user.id
    row.submitted_at = datetime.now(timezone.utc)
    row.reviewed_by = None
    row.reviewed_at = None
    row.remarks = None
    row.version += 1
    db.flush()
    save(db, event, user, "closure_document_uploaded", {"document_id": str(row.id), "version": row.version, "previous_reference": previous})
    return document_out(row)


@router.post("/post-activity/documents/{document_id}/review")
def review_closure_document(event_id: uuid.UUID, document_id: uuid.UUID, payload: DocumentReview,
                            db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user, write=True, states={"approved", "completed"})
    row = event_record(db, EventComplianceDocument, event, document_id)
    if row.kind not in REPORT_KINDS or (row.kind != "signed_attendance" and event.status != "completed") or row.status != "SUBMITTED" or row.version != payload.version:
        raise HTTPException(409, "Review the current closure document at its applicable event stage")
    row.status = payload.decision
    row.reviewed_by = user.id
    row.reviewed_at = datetime.now(timezone.utc)
    row.remarks = payload.remarks
    row.version += 1
    save(db, event, user, "closure_document_reviewed", {"document_id": str(row.id), **payload.model_dump()})
    return document_out(row)


def parallel_out(row):
    return {**public_row(row, "id event_id participant_id title learning_objectives instructions reason due_date is_active status version evidence_mode reviewed_by reviewed_at remarks"),
        "has_document": bool(row.document_url)}


@router.post("/parallel-activities", status_code=201)
def assign_parallel_activity(event_id: uuid.UUID, payload: ParallelAssignment, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user, write=True, states={"draft", "rejected", "completed"})
    participant = event_record(db, EventParticipant, event, payload.participant_id)
    if not participant.is_active:
        raise HTTPException(409, "Reactivate the roster entry before assigning a parallel activity")
    row = db.query(EventParallelActivity).filter_by(event_id=event.id, participant_id=participant.id).first()
    if (row.version if row else 0) != payload.version:
        raise HTTPException(409, "The parallel assignment changed; refresh")
    previous_reference = row.document_url if row else None
    if row is None:
        row = EventParallelActivity(event_id=event.id, participant_id=participant.id, version=0)
        db.add(row)
    for key, value in payload.model_dump(exclude={"participant_id", "version"}).items():
        setattr(row, key, value)
    row.assigned_by = user.id
    row.status = "ASSIGNED"
    row.is_active = True
    row.document_url = None
    row.evidence_mode = None
    row.submitted_by = None
    row.submitted_at = None
    row.reviewed_by = None
    row.reviewed_at = None
    row.remarks = None
    row.version += 1
    participant.participation_mode = "parallel"
    db.flush()
    save(db, event, user, "parallel_activity_assigned", {"activity_id": str(row.id), "participant_id": str(participant.id), "version": row.version, "previous_reference": previous_reference})
    return parallel_out(row)


@router.patch("/participants/{participant_id}/participation")
def restore_attending(event_id: uuid.UUID, participant_id: uuid.UUID, payload: ParticipationUpdate,
                       db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user, write=True, states={"draft", "rejected", "completed"})
    participant = event_record(db, EventParticipant, event, participant_id)
    participant.participation_mode = "attending"
    row = db.query(EventParallelActivity).filter_by(event_id=event.id, participant_id=participant.id).first()
    if row:
        row.is_active = False
        row.version += 1
    db.flush()
    sync_compliance_records(db, event, "post_activity" if event.status == "completed" else "pre_activity")
    save(db, event, user, "participation_restored", {"participant_id": str(participant.id), "remarks": payload.remarks})
    return {"id": participant.id, "participation_mode": participant.participation_mode}


@router.post("/parallel-activities/{activity_id}/upload")
async def upload_parallel_work(event_id: uuid.UUID, activity_id: uuid.UUID, version: int = Form(ge=1), file: UploadFile = File(...),
                               db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user, write=True, states={"approved", "completed"})
    row = event_record(db, EventParallelActivity, event, activity_id)
    participant = db.get(EventParticipant, row.participant_id)
    if row.version != version or not row.is_active or not participant.is_active or participant.participation_mode != "parallel":
        raise HTTPException(409, "Refresh the active parallel assignment")
    reference = await store_document(file, user.id, event.organization_id)
    previous = row.document_url
    row.document_url = reference
    row.status = "SUBMITTED"
    row.evidence_mode = "digital"
    row.submitted_by = user.id
    row.submitted_at = datetime.now(timezone.utc)
    row.reviewed_by = None
    row.reviewed_at = None
    row.remarks = None
    row.version += 1
    save(db, event, user, "parallel_work_uploaded", {"activity_id": str(row.id), "version": row.version, "previous_reference": previous})
    return parallel_out(row)


@router.post("/parallel-activities/{activity_id}/review")
def review_parallel_work(event_id: uuid.UUID, activity_id: uuid.UUID, payload: BatchReview,
                         db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user, write=True, states={"approved", "completed"})
    row = event_record(db, EventParallelActivity, event, activity_id)
    participant = db.get(EventParticipant, row.participant_id)
    if len(payload.records) != 1 or payload.records[0].id != row.id or payload.records[0].version != row.version or not row.is_active or not participant.is_active or participant.participation_mode != "parallel":
        raise HTTPException(409, "Select only this active assignment's current version")
    if payload.evidence_mode == "digital" and (not row.document_url or row.status != "SUBMITTED"):
        raise HTTPException(409, "Digital verification requires submitted parallel work")
    row.status = payload.decision
    row.evidence_mode = payload.evidence_mode
    row.reviewed_by = user.id
    row.reviewed_at = datetime.now(timezone.utc)
    row.remarks = payload.remarks
    row.version += 1
    save(db, event, user, "parallel_work_reviewed", {"activity_id": str(row.id), "version": row.version, "decision": payload.decision, "evidence_mode": payload.evidence_mode, "remarks": payload.remarks})
    return parallel_out(row)


@router.get("/parallel-activities/{activity_id}/file")
def parallel_work_file(event_id: uuid.UUID, activity_id: uuid.UUID, db: Session = Depends(get_db), user: User = Depends(staff)):
    event = scoped_event(db, event_id, user)
    row = event_record(db, EventParallelActivity, event, activity_id)
    return file_access(row.document_url)
