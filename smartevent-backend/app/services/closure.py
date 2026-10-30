"""Staff-managed post-activity evidence and parallel learning activities."""
from datetime import datetime, timezone

from fastapi import HTTPException

from app.dependencies import assert_record_scope
from app.models import Event, EventParticipant, EventRequirement, RequirementPreset, StudentComplianceRecord
from app.models_compliance import EventComplianceDocument, EventParallelActivity
from app.services.academic_year import institution_today  # noqa: F401 - re-exported for routers and sap
from app.services.compliance import event_record, sync_compliance_records

REPORT_KINDS = {"signed_attendance", "debriefing_report", "final_expense_report"}


def scoped_event(db, event_id, user, *, write=False, states=None):
    query = db.query(Event).filter(Event.id == event_id)
    event = (query.with_for_update() if write else query).first()
    if event is None:
        raise HTTPException(404, "Event not found")
    assert_record_scope(user, event)
    if states is not None and event.status not in states:
        raise HTTPException(409, "This action is not available at the event's current stage")
    return event


def ensure_post_requirements(db, event):
    preset = db.query(RequirementPreset).filter_by(code="student_learning_journal", phase="post_activity").first()
    if preset is None:
        raise HTTPException(409, "Apply the requirement-presets migration before completing an event")
    requirement = db.query(EventRequirement).filter_by(event_id=event.id, preset_id=preset.id).first()
    if requirement is None:
        db.add(EventRequirement(event_id=event.id, preset_id=preset.id, name=preset.name,
            description=preset.description, phase="post_activity", is_required=True,
            requires_notarization=preset.requires_notarization, is_sensitive=preset.is_sensitive))
        db.flush()
    elif requirement.phase != "post_activity":
        raise HTTPException(409, "Correct the learning-journal requirement's phase before initialization")
    else:
        requirement.is_required = True
    sync_compliance_records(db, event, "post_activity")


def review_student_records(db, event, user, payload, phase):
    rows = []
    for selection in payload.records:
        row = event_record(db, StudentComplianceRecord, event, selection.id)
        participant = db.get(EventParticipant, row.participant_id)
        requirement = db.get(EventRequirement, row.requirement_id)
        if row.version != selection.version or not participant.is_active or participant.participation_mode != "attending" or requirement.phase != phase:
            raise HTTPException(409, "Refresh the active participant's current document record")
        if payload.evidence_mode == "digital" and (not row.document_url or row.status != "SUBMITTED"):
            raise HTTPException(409, "Digital verification requires a submitted file")
        if payload.decision == "VERIFIED" and requirement.requires_notarization and not payload.notarization_confirmed:
            raise HTTPException(422, "Confirm notarization for every selected consent requirement")
        rows.append(row)
    for row in rows:
        row.status = payload.decision
        row.evidence_mode = payload.evidence_mode
        row.notarization_confirmed = payload.notarization_confirmed if payload.decision == "VERIFIED" else False
        row.reviewed_by = user.id
        row.reviewed_at = datetime.now(timezone.utc)
        row.remarks = payload.remarks
        row.version += 1
    return rows


def closeout_readiness(db, event):
    participants = db.query(EventParticipant).filter_by(event_id=event.id, is_active=True).all()
    attending = [row for row in participants if row.participation_mode == "attending"]
    requirements = db.query(EventRequirement).filter_by(event_id=event.id, phase="post_activity", is_required=True).all()
    records = {(row.participant_id, row.requirement_id): row for row in db.query(StudentComplianceRecord).filter_by(event_id=event.id)}
    missing = sum(1 for participant in attending for requirement in requirements
        if (record := records.get((participant.id, requirement.id))) is None or record.status != "VERIFIED"
        or (requirement.requires_notarization and not record.notarization_confirmed))
    blockers = []
    if event.status != "completed":
        blockers.append("Complete the event to unlock post-activity submissions")
    journal = db.query(EventRequirement.id).join(RequirementPreset,
        EventRequirement.preset_id == RequirementPreset.id).filter(
        EventRequirement.event_id == event.id, EventRequirement.phase == "post_activity",
        EventRequirement.is_required.is_(True), RequirementPreset.code == "student_learning_journal").first()
    if attending and journal is None:
        blockers.append("Initialize the post-activity learning-journal requirement")
    if missing:
        blockers.append(f"{missing} required post-activity student document(s) are not verified")
    documents = {row.kind: row for row in db.query(EventComplianceDocument).filter_by(event_id=event.id, vehicle_id=None)}
    required_reports = REPORT_KINDS if attending else REPORT_KINDS - {"signed_attendance"}
    for kind in sorted(required_reports):
        if kind not in documents or documents[kind].status != "VERIFIED":
            blockers.append("Verify " + kind.replace("_", " "))
    parallel = {row.participant_id: row for row in db.query(EventParallelActivity).filter_by(event_id=event.id, is_active=True)}
    missing_parallel = sum(1 for student in participants if student.participation_mode == "parallel"
        and (student.id not in parallel or parallel[student.id].status != "VERIFIED"))
    if missing_parallel:
        blockers.append(f"{missing_parallel} parallel activity/activities need verification")
    return {"ready": not blockers, "blockers": blockers, "unverified_document_count": missing,
        "unverified_parallel_count": missing_parallel, "status": "CLOSED" if not blockers else "OPEN"}
