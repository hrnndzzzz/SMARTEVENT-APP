"""Transactional SAP boundary: event lock, optimistic version, immutable submissions."""
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import secrets
from fastapi import HTTPException
from app.dependencies import assert_record_scope
from app.models import Event, User, Notification
from app.models_compliance import EventLogistics
from app.models_sap import SAPProposal, SAPItem, SAPRevision, SAPCheckpoint, SAPEvaluation
from app.schemas_sap import validate_submission
from app.services.sap_pdf import signature_slots, render_proposal
from app.services.access_audit import record_access_change
from app.services.compliance import invalidate_clearance, require_pre_activity_clearance
from app.services.academic_year import validate_school_year


def now():
    return datetime.now(timezone.utc)


def load(db, event_id, user, *, write=False, sds=False, proposer=False, required=True):
    query = db.query(Event).filter_by(id=event_id)
    event = (query.with_for_update() if write else query).first()
    if event is None:
        raise HTTPException(404, 'Event not found')
    if sds and user.role != 'sds_staff':
        raise HTTPException(403, 'Only SDS staff can record paper evidence or edit Parts 4 and 6')
    if user.role != 'sds_staff':
        assert_record_scope(user, event, allow_officer_read=not write)
    if proposer and (user.id != event.proposed_by or user.role not in {'treasurer', 'adviser', 'admin', 'super_admin'}):
        raise HTTPException(403, 'Only the authorized event proposer may edit Parts 1–3')
    proposal = db.query(SAPProposal).filter_by(event_id=event.id).first()
    if required and proposal is None:
        raise HTTPException(404, 'SAP proposal not found')
    return event, proposal


def check_version(proposal, version, editable=False):
    if proposal.version != version:
        raise HTTPException(409, 'Proposal changed; reload before retrying')
    if editable and proposal.state not in {'draft', 'revision_requested'}:
        raise HTTPException(409, 'Only draft or returned proposals can be edited')


def collections(db, proposal):
    result = {key: [] for key in ('program-flow', 'budget-items', 'support-requests', 'affected-classes')}
    for row in db.query(SAPItem).filter_by(proposal_id=proposal.id).order_by(SAPItem.ordinal):
        result[row.kind].append(row.data)
    return result


def snapshot(db, proposal):
    return dict(form_code=proposal.form_code, form_version=proposal.form_version,
                details=proposal.details, clearance=proposal.clearance, collections=collections(db, proposal))


def revision(db, proposal, number=None):
    row = db.query(SAPRevision).filter_by(proposal_id=proposal.id, revision_no=number or proposal.revision_no).first()
    if row is None:
        raise HTTPException(404, 'Submitted revision not found')
    return row


def steps(db, rev):
    return db.query(SAPCheckpoint).filter_by(revision_id=rev.id).order_by(SAPCheckpoint.slot).all()


def prerequisites(slot):
    return [] if slot == 1 else [1] if slot in (2, 3) else list(range(1, slot))


def workflow(db, proposal):
    rows = steps(db, revision(db, proposal)) if proposal.revision_no else []
    signed = {row.slot for row in rows if row.evidence}
    return {'state': proposal.state, 'revision_no': proposal.revision_no, 'version': proposal.version,
            'completed_count': len(signed), 'total_count': 9,
            'steps': [dict(id=row.id, slot=row.slot, position=row.position, display_label=row.label,
                           revision_no=proposal.revision_no, status='recorded' if row.evidence else 'pending',
                           actionable=proposal.state == 'pending_sap_review' and not row.evidence and set(prerequisites(row.slot)) <= signed,
                           evidence=row.evidence, recorded_by=row.recorded_by, recorded_at=row.recorded_at)
                      for row in rows]}


def output(db, proposal):
    evaluation = db.query(SAPEvaluation).filter_by(proposal_id=proposal.id).first()
    return dict(id=proposal.id, event_id=proposal.event_id, state=proposal.state, version=proposal.version,
                revision_no=proposal.revision_no, return_remarks=proposal.return_remarks, **snapshot(db, proposal),
                evaluation=None if evaluation is None else dict(outcome=evaluation.outcome, remarks=evaluation.remarks,
                    evaluated_by=evaluation.evaluated_by, evaluated_at=evaluation.evaluated_at))


def save(db, event, proposal, user, action, *, notify=False, details=None):
    proposal.version += 1
    record_access_change(db, user, action, event, details or {'proposal_id': str(proposal.id), 'revision': proposal.revision_no})
    if notify:
        recipients = {event.proposed_by} | {row.id for row in db.query(User).filter_by(role='sds_staff', is_active=True, is_suspended=False)}
        for recipient in recipients:
            db.add(Notification(user_id=recipient, kind='sap_workflow', title='SAP proposal updated',
                body=f'Proposal {proposal.id}, revision {proposal.revision_no}: {proposal.state}. Open SMARTEVENT for details.', email_status='pending'))
    db.commit()
    return output(db, proposal)


def sync_event(db, event, d):
    """Project complete draft details early, while compliance can still be corrected."""
    logistics = db.get(EventLogistics, event.id)
    if (event.event_date != d.activity_date or event.start_time != d.start_time or event.end_time != d.end_time
            or (logistics and (logistics.destination != d.venue or logistics.activity_location != d.setting))):
        invalidate_clearance(db, event)
    event.title, event.description = d.title, d.rationale
    event.event_date, event.estimated_cost = d.activity_date, d.total_budget
    event.start_time, event.end_time = d.start_time, d.end_time
    event.school_year, event.event_scope = d.school_year, d.scope
    if logistics is None:
        logistics = EventLogistics(event_id=event.id)
        db.add(logistics)
    logistics.activity_location, logistics.destination, logistics.transport_mode = d.setting, d.venue, 'none'


def submit(db, event, proposal, user, verification_base):
    data = snapshot(db, proposal)
    try:
        d = validate_submission(data['details'], data['collections'], data['clearance'])
        validate_school_year(d.school_year)
        if event.semester not in {'1st', '2nd', 'summer'}:
            raise ValueError('Set the event semester before submission')
        # Allocation remains controlled by the existing financial workflow.
        if d.total_budget > Decimal(event.allocated_budget or 0):
            raise ValueError('Proposal budget exceeds the event allocation; update allocation through the budget workflow first')
        token = secrets.token_urlsafe(32)
        number = proposal.revision_no + 1
        pdf = render_proposal(data, number, verification_base.rstrip('/') + '/' + token)
    except (ValueError, TypeError) as exc:
        raise HTTPException(422, str(exc)) from None
    sync_event(db, event, d)
    db.flush()
    require_pre_activity_clearance(db, event)
    row = SAPRevision(proposal_id=proposal.id, revision_no=number, snapshot=data,
        printable_pdf=pdf, pdf_sha256=hashlib.sha256(pdf).hexdigest(), verification_token=token, submitted_by=user.id)
    db.add(row)
    db.flush()
    for slot, (position, label) in enumerate(signature_slots(data['details']), 1):
        db.add(SAPCheckpoint(revision_id=row.id, slot=slot, position=position, label=label))
    proposal.revision_no, proposal.state, proposal.return_remarks = number, 'pending_sap_review', None
    event.status = 'pending_institutional_review'
    return save(db, event, proposal, user, 'sap_submitted', notify=True)


def assert_generic_workflow(db, event):
    if db.query(SAPProposal.id).filter_by(event_id=event.id).first():
        raise HTTPException(409, 'This event uses SAP; use the SAP proposal endpoints')
