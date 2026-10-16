"""Pre-activity gates use stored, reviewed evidence, never client totals."""

from datetime import datetime, timezone

from fastapi import HTTPException

from app.config import settings
from app.dependencies import assert_owner_or_admin, assert_record_scope
from app.models import Event, EventParticipant, EventRequirement, RequirementPreset, StudentComplianceRecord
from app.models_compliance import EventComplianceDocument, EventLogistics, EventPersonnel, EventVehicle
from app.services.storage import MAX_UPLOAD_BYTES, SIGNED_URL_SECONDS, StorageError, prepare_image_for_upload, signed_file_url, upload_proposal_letter

EDITABLE = {"draft", "rejected"}
COLLECTING = EDITABLE | {"pending", "pending_adviser", "pending_admin"}
VEHICLE_DOCUMENTS = {"vehicle_registration", "insurance", "driver_license", "roadworthiness"}
THIRD_PARTY_DOCUMENTS = {"ltfrb_franchise", "dot_accreditation"}
EVENT_DOCUMENTS = {"lgu_coordination", "agency_acknowledgment"}
DEFAULT_PRESETS = {"parent_guardian_consent", "medical_clearance"}
MAX_STUDENTS_PER_PIC = 50


def event_for_compliance(db, event_id, user, *, write=False, structure=False, owner=False):
    query = db.query(Event).filter(Event.id == event_id)
    event = (query.with_for_update() if write else query).first()
    if event is None:
        raise HTTPException(404, "Event not found")
    assert_record_scope(user, event, allow_officer_read=not write)
    if owner:
        assert_owner_or_admin(event.proposed_by, user, "manage event logistics")
    if write and event.status not in (EDITABLE if structure else COLLECTING):
        raise HTTPException(409, "Edit the draft/rejected proposal or collect documents before institutional review")
    return event


def event_record(db, model, event, record_id):
    record = db.query(model).filter(model.id == record_id, model.event_id == event.id).first()
    if record is None:
        raise HTTPException(404, "Event record not found")
    return record


def sync_compliance_records(db, event, phase="pre_activity"):
    # Parent event is locked by every writer, including uploads and final approval.
    participant_ids = [row.id for row in db.query(EventParticipant).filter_by(event_id=event.id, is_active=True, participation_mode="attending")]
    requirement_ids = [row.id for row in db.query(EventRequirement).filter_by(event_id=event.id, phase=phase)]
    existing = {(row.participant_id, row.requirement_id) for row in
                db.query(StudentComplianceRecord).filter_by(event_id=event.id)}
    db.add_all([StudentComplianceRecord(event_id=event.id, participant_id=participant_id, requirement_id=requirement_id)
                for participant_id in participant_ids for requirement_id in requirement_ids
                if (participant_id, requirement_id) not in existing])
    db.flush()


def add_default_requirements(db, event):
    presets = db.query(RequirementPreset).filter(RequirementPreset.code.in_(DEFAULT_PRESETS)).all()
    if {preset.code for preset in presets} != DEFAULT_PRESETS:
        raise HTTPException(409, "Apply the requirement-presets migration before configuring an off-campus event")
    for preset in presets:
        requirement = db.query(EventRequirement).filter_by(event_id=event.id, preset_id=preset.id).first()
        if requirement is None:
            db.add(EventRequirement(event_id=event.id, preset_id=preset.id, name=preset.name,
                description=preset.description, phase=preset.phase, is_required=True,
                requires_notarization=preset.requires_notarization, is_sensitive=preset.is_sensitive))
        else:
            requirement.is_required = True
            requirement.requires_notarization = preset.requires_notarization
    db.flush()
    sync_compliance_records(db, event)


def readiness(db, event):
    logistics = db.get(EventLogistics, event.id)
    participants = db.query(EventParticipant).filter_by(event_id=event.id, is_active=True, participation_mode="attending").all()
    personnel = db.query(EventPersonnel).filter_by(event_id=event.id, is_active=True).count()
    requirements = db.query(EventRequirement).filter_by(event_id=event.id, phase="pre_activity", is_required=True).all()
    records = {(row.participant_id, row.requirement_id): row for row in
               db.query(StudentComplianceRecord).filter_by(event_id=event.id)}
    missing = sum(1 for participant in participants for requirement in requirements
        if (record := records.get((participant.id, requirement.id))) is None
        or record.status != "VERIFIED"
        or (requirement.requires_notarization and not record.notarization_confirmed))
    blockers = []
    if logistics is None:
        blockers.append("Classify the activity as on-campus or off-campus and save logistics")
    if missing:
        blockers.append(f"{missing} required participant document(s) are not verified")
    if logistics is not None and logistics.activity_location == "off_campus":
        if event.event_date is None:
            blockers.append("Set the activity date before verifying transport validity")
        if not participants:
            blockers.append("Add at least one participating student")
        if personnel == 0 or len(participants) > personnel * MAX_STUDENTS_PER_PIC:
            blockers.append(f"Assign at least {max(1, (len(participants) + 49) // 50)} qualified PIC(s); maximum 50 students per PIC")
        preset_codes = {code for (code,) in db.query(RequirementPreset.code).join(
            EventRequirement, EventRequirement.preset_id == RequirementPreset.id).filter(
            EventRequirement.event_id == event.id, EventRequirement.phase == "pre_activity", EventRequirement.is_required.is_(True))}
        if not DEFAULT_PRESETS.issubset(preset_codes):
            blockers.append("Consent and medical-clearance requirements must remain required")
        evidence = {(str(row.vehicle_id) if row.vehicle_id else None, row.kind): row
                    for row in db.query(EventComplianceDocument).filter_by(event_id=event.id)}
        for kind in sorted(EVENT_DOCUMENTS):
            document = evidence.get((None, kind))
            if document is None or document.status != "VERIFIED":
                blockers.append(f"Verify {kind.replace('_', ' ')} evidence")
        vehicles = db.query(EventVehicle).filter_by(event_id=event.id, is_active=True).all()
        if logistics.transport_mode == "none":
            if not logistics.transport_notes:
                blockers.append("Explain why no vehicle transport is required")
            if vehicles:
                blockers.append("Deactivate vehicles or select the applicable transport mode")
        else:
            if not vehicles:
                blockers.append("Add the event's vehicle(s)")
            kinds = VEHICLE_DOCUMENTS | (THIRD_PARTY_DOCUMENTS if logistics.transport_mode == "third_party" else set())
            for vehicle in vehicles:
                vehicle_kinds = kinds | ({"ltfrb_special_permit"} if vehicle.out_of_line and logistics.transport_mode == "third_party" else set())
                for kind in sorted(vehicle_kinds):
                    document = evidence.get((str(vehicle.id), kind))
                    if (document is None or document.status != "VERIFIED" or not document.validity_confirmed
                            or (document.valid_until is not None and event.event_date is not None and document.valid_until < event.event_date)):
                        blockers.append(f"Vehicle {vehicle.plate_number}: verify {kind.replace('_', ' ')}")
    return {"event_id": str(event.id), "activity_location": logistics.activity_location if logistics else None,
        "participant_count": len(participants), "pic_count": personnel, "max_students_per_pic": MAX_STUDENTS_PER_PIC,
        "required_pic_count": max(1, (len(participants) + 49) // 50) if logistics and logistics.activity_location == "off_campus" else 0,
        "unverified_document_count": missing, "ready": not blockers, "blockers": blockers}


def require_pre_activity_clearance(db, event):
    result = readiness(db, event)
    if not result["ready"]:
        raise HTTPException(409, {"message": "Pre-activity compliance is incomplete", "blockers": result["blockers"]})


def invalidate_clearance(db, event):
    """A changed date/destination needs fresh review; keep files and audit history."""
    students = db.query(StudentComplianceRecord).filter_by(event_id=event.id).all()
    documents = db.query(EventComplianceDocument).filter_by(event_id=event.id).all()
    for row in students + documents:
        row.status = "SUBMITTED" if row.document_url else "MISSING"
        row.reviewed_by = None
        row.reviewed_at = None
        row.remarks = None
        row.version += 1
    for row in students:
        row.notarization_confirmed = False
    for row in documents:
        row.validity_confirmed = False


async def store_document(file, owner_id, organization_id):
    if organization_id is None:
        raise HTTPException(409, "Assign the event to an organization first")
    raw = await file.read(MAX_UPLOAD_BYTES + 1)
    if not raw or len(raw) > MAX_UPLOAD_BYTES:
        raise HTTPException(400, "File must be between 1 byte and 10 MB")
    content_type = file.content_type
    if content_type == "application/pdf":
        if not raw.startswith(b"%PDF-") or b"%%EOF" not in raw[-1024:]:
            raise HTTPException(400, "Upload a valid PDF document")
        extension = "pdf"
    elif content_type in {"image/jpeg", "image/png"}:
        try:
            raw, content_type = prepare_image_for_upload(raw)
        except Exception:
            raise HTTPException(400, "Could not process the document image") from None
        extension = "jpg"
    else:
        raise HTTPException(400, "Allowed document types: PDF, JPEG, PNG")
    try:
        return upload_proposal_letter(raw, content_type, extension, owner_id, organization_id)
    except (RuntimeError, StorageError):
        raise HTTPException(503, "Private document storage is unavailable") from None


def file_access(reference):
    if not reference:
        raise HTTPException(404, "No digital document is attached")
    try:
        return {"url": signed_file_url(reference, settings.supabase_proposal_letters_bucket), "expires_in": SIGNED_URL_SECONDS}
    except (RuntimeError, StorageError, ValueError):
        raise HTTPException(503, "Private document access is unavailable") from None


def replace_submission(record, reference, actor_id):
    record.document_url = reference
    record.submitted_by = actor_id
    record.submitted_at = datetime.now(timezone.utc)
    record.status = "SUBMITTED"
    record.evidence_mode = "digital"
    record.notarization_confirmed = False
    record.reviewed_by = None
    record.reviewed_at = None
    record.remarks = None
    record.version += 1
