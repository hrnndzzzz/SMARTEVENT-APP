"""Transactional SAP boundary: event lock, optimistic version, immutable submissions."""
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import secrets
from fastapi import HTTPException
from app.dependencies import assert_record_scope
from app.rbac_policy import can_propose_events
from app.models import Event, User, Notification
from app.models_compliance import EventLogistics
from app.models_sap import SAPProposal, SAPItem, SAPRevision, SAPCheckpoint, SAPEvaluation, SAPAttachment, SAPReview
from app.schemas_sap import validate_submission
from app.services.sap_pdf import signature_slots, render_proposal
from app.services.access_audit import record_access_change
from app.services.approvals import record_decision
from app.services.compliance import invalidate_clearance, require_pre_activity_clearance
from app.services.academic_year import validate_school_year
from app.services.closure import institution_today


def now():
    return datetime.now(timezone.utc)


def load(db, event_id, user, *, write=False, sds=False, proposer=False, owner=False, required=True):
    query = db.query(Event).filter_by(id=event_id)
    event = (query.with_for_update() if write else query).first()
    if event is None:
        raise HTTPException(404, 'Event not found')
    if sds and user.role != 'sds_staff':
        raise HTTPException(403, 'Only SDS staff can record paper evidence or edit Parts 4 and 6')
    if user.role != 'sds_staff':
        assert_record_scope(user, event, allow_officer_read=not write or (proposer and can_propose_events(user)))
    if proposer and not can_propose_events(user):
        raise HTTPException(403, 'Only an authorized event proposer may edit Parts 1–3')
    # Any proposer in scope may write a draft. Members are held to their own organization
    # above, so they may also send or withdraw a colleague's; an admin sends only their own.
    if owner and user.id != event.proposed_by and user.role not in {'adviser', 'treasurer', 'officer'}:
        raise HTTPException(403, "Only the proposer or a member of the event's organization may send or withdraw it")
    proposal = db.query(SAPProposal).filter_by(event_id=event.id).first()
    if required and proposal is None:
        raise HTTPException(404, 'SAP proposal not found')
    if user.role == 'sds_staff' and proposal is not None and not proposal.seen_by_sds:
        raise HTTPException(403, 'The SDS Office sees a proposal once the Dean has approved it')
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


def snapshot(db, proposal, revision_no=None):
    number = revision_no or (proposal.revision_no + 1 if proposal.state in {'draft', 'revision_requested'} else proposal.revision_no)
    attachments = db.query(SAPAttachment).filter_by(proposal_id=proposal.id, revision_no=number).order_by(SAPAttachment.uploaded_at).all()
    return dict(form_code=proposal.form_code, form_version=proposal.form_version,
                details=proposal.details, clearance=proposal.clearance, collections=collections(db, proposal),
                attachments=[dict(id=str(row.id), category=row.category, display_name=row.display_name,
                                  file_name=row.file_name, content_type=row.content_type, sha256=row.sha256,
                                  uploaded_at=row.uploaded_at.isoformat()) for row in attachments])


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
                           actionable=proposal.state in {'pending_sap_review', 'sds_signed'} and (row.slot < 5 or proposal.state == 'sds_signed') and not row.evidence and set(prerequisites(row.slot)) <= signed,
                           evidence=row.evidence, recorded_by=row.recorded_by, recorded_at=row.recorded_at)
                      for row in rows]}


def output(db, proposal):
    review = db.query(SAPReview).join(SAPRevision, SAPReview.revision_id == SAPRevision.id).filter(SAPRevision.proposal_id == proposal.id, SAPRevision.revision_no == proposal.revision_no).first() if proposal.revision_no else None
    evaluation = db.query(SAPEvaluation).filter_by(proposal_id=proposal.id).first()
    return dict(id=proposal.id, event_id=proposal.event_id, state=proposal.state, version=proposal.version,
                revision_no=proposal.revision_no, return_remarks=proposal.return_remarks, returned_by=proposal.returned_by, **snapshot(db, proposal),
                sds_review=None if review is None else dict(overall_remarks=review.overall_remarks, section_remarks=review.section_remarks, signed_by=str(review.signed_by) if review.signed_by else None, signed_at=review.signed_at.isoformat() if review.signed_at else None, signed_pdf_sha256=review.signed_pdf_sha256),
                evaluation=None if evaluation is None else dict(outcome=evaluation.outcome, remarks=evaluation.remarks,
                    evaluated_by=evaluation.evaluated_by, evaluated_at=evaluation.evaluated_at))


def save(db, event, proposal, user, action, *, notify=False, details=None, notify_sds=True):
    proposal.version += 1
    record_access_change(db, user, action, event, details or {'proposal_id': str(proposal.id), 'revision': proposal.revision_no})
    if notify:
        title, message = {
            'sap_submitted': ('SAP proposal submitted', 'Sent for department review: {title}.'),
            'sap_returned': ('SAP proposal returned', '{title} was returned for changes.'),
            'sap_signed_revision_correction_requested': ('SAP correction requested', '{title} was returned for changes.'),
            'sap_revision_signed': ('SAP proposal signed by SDS', 'The SDS Office has signed {title}. Physical approval is still pending.'),
            'sap_approved_with_physical_evidence': ('SAP proposal approved', 'The SDS Office has approved {title}.'),
            'sap_evaluated': ('SAP evaluation completed', 'The SDS Office recorded the final evaluation for {title}.'),
            'sap_withdrawn': ('SAP proposal withdrawn', '{title} was withdrawn by its proposer for editing.'),
            'sap_checkpoint_recorded': ('SAP signature checkpoint recorded', 'A physical signature checkpoint was recorded for {title}.'),
            'sap_dean_approved': ('SAP proposal sent to the SDS Office', 'The Dean approved {title}. It is now with the SDS Office.'),
            'sap_department_returned': ('SAP proposal returned', '{title} was returned for changes.'),
            'sap_rejected': ('SAP proposal rejected', 'The SDS Office rejected {title}.'),
        }.get(action, ('SAP proposal updated', '{title} has been updated.'))
        payload = {'event_id': str(event.id), 'proposal_id': str(proposal.id),
                   'revision_no': proposal.revision_no, 'state': proposal.state, 'action': action}
        recipients = {event.proposed_by}
        if notify_sds:
            recipients |= {row.id for row in db.query(User).filter_by(role='sds_staff', is_active=True, is_suspended=False)}
        for recipient in recipients:
            db.add(Notification(user_id=recipient, kind='sap_workflow', title=title,
                body=message.format(title=event.title), payload=payload, email_status='pending'))
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
        if (d.activity_date - institution_today()).days < 30:
            raise ValueError('Submit at least 30 calendar days before the activity')
        if d.setting == 'off_campus' and not db.query(SAPAttachment.id).filter_by(proposal_id=proposal.id, revision_no=proposal.revision_no + 1, category='roc_coc').first():
            raise ValueError('Off-campus activities require an ROC/COC attachment for this revision')
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
    proposal.revision_no, proposal.state, proposal.return_remarks, proposal.returned_by = number, 'pending_department_review', None, None
    # A Moderator does not approve their own proposal, so one they sent or created starts with the Dean.
    creator = db.get(User, event.proposed_by)
    event.status = 'pending_admin' if 'adviser' in (user.role, creator.role) else 'pending_adviser'
    return save(db, event, proposal, user, 'sap_submitted', notify=True, notify_sds=False)


def assert_generic_workflow(db, event):
    if db.query(SAPProposal.id).filter_by(event_id=event.id).first():
        raise HTTPException(409, 'This event uses SAP; use the SAP proposal endpoints')


def withdraw(db, event, proposal, user):
    """Caller holds the event lock and has checked ownership and version."""
    if proposal.state not in {'pending_department_review', 'pending_sap_review'}:
        raise HTTPException(409, 'Only a proposal still waiting on review can be withdrawn')
    with_sds = proposal.state == 'pending_sap_review'
    rev = revision(db, proposal)
    if (db.query(SAPReview.revision_id).filter_by(revision_id=rev.id).first()
            or db.query(SAPCheckpoint.id).filter(
                SAPCheckpoint.revision_id == rev.id, SAPCheckpoint.evidence.is_not(None)).first()):
        raise HTTPException(409, 'SDS review has started; request a return for changes')
    # Keep old rows referenced by submitted snapshots. Only metadata is copied;
    # both revisions retain the same private file and original upload attribution.
    for row in db.query(SAPAttachment).filter_by(
            proposal_id=proposal.id, revision_no=proposal.revision_no).all():
        db.add(SAPAttachment(proposal_id=proposal.id, revision_no=proposal.revision_no + 1,
            category=row.category, display_name=row.display_name, file_name=row.file_name,
            content_type=row.content_type, storage_ref=row.storage_ref, sha256=row.sha256,
            uploaded_by=row.uploaded_by, uploaded_at=row.uploaded_at))
    proposal.state, proposal.clearance = 'draft', None
    event.status = 'draft'
    return save(db, event, proposal, user, 'sap_withdrawn', notify=True, notify_sds=with_sds)


def department_review(db, event, proposal, user, decision, remarks):
    """The Moderator, then the Dean, decide a sent proposal before the SDS Office sees it.
    Caller holds the event lock and has run assert_event_read and assert_not_self_review."""
    if decision not in {'approved', 'returned'}:
        raise ValueError(f"decision must be 'approved' or 'returned', not {decision!r}")
    if proposal.state != 'pending_department_review':
        raise HTTPException(409, 'This proposal is not waiting on department review')
    if user.role == 'adviser':
        if event.status != 'pending_adviser':
            raise HTTPException(409, 'This proposal is with the Dean')
    elif user.role in {'admin', 'super_admin'}:
        if decision == 'approved' and event.status != 'pending_admin':
            raise HTTPException(409, 'The Moderator approves a proposal before the Dean')
    else:
        raise HTTPException(403, 'Only the Moderator or the Dean can review a proposal here')
    if decision == 'returned':
        if not (remarks or '').strip():
            raise HTTPException(422, 'Say what needs to change')
        proposal.state, proposal.return_remarks, proposal.clearance = 'revision_requested', remarks, None
        proposal.returned_by = 'moderator' if user.role == 'adviser' else 'dean'
        event.status = 'draft'
        record_decision(db, 'event', event.id, 'returned', user, remarks)
        return save(db, event, proposal, user, 'sap_department_returned', notify=True, notify_sds=False,
                    details={'revision': proposal.revision_no, 'remarks': remarks, 'returned_by': proposal.returned_by})
    if user.role == 'adviser':
        record_decision(db, 'event', event.id, 'approved', user, remarks)
        event.status = 'pending_admin'
        return save(db, event, proposal, user, 'sap_moderator_approved')
    # Compliance stays open during department review, so check readiness again before the SDS Office gets it.
    require_pre_activity_clearance(db, event)
    record_decision(db, 'event', event.id, 'approved', user, remarks)
    proposal.state, event.status = 'pending_sap_review', 'pending_institutional_review'
    return save(db, event, proposal, user, 'sap_dean_approved', notify=True)
