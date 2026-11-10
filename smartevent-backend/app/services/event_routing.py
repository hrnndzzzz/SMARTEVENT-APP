"""Event-specific institutional authorization; never grants operational access."""

from datetime import datetime, timezone

from fastapi import HTTPException

from app.dependencies import assert_not_self_review, assert_record_scope, require_role, scope_query_by_department
from app.models import DocumentRouting, Event, User
from app.models_sap import SAPProposal
from app.services.access_audit import record_access_change
from app.services.approvals import record_decision
from app.services.compliance import require_pre_activity_clearance

INSTITUTIONAL_REVIEW = "pending_institutional_review"
require_event_reader = require_role("admin", "adviser", "treasurer", "officer", "signatory", "sds_staff")


def _sent_proposal_events(db):
    """Events whose SAP proposal has reached the SDS Office: its work. Until then it is the
    proposer's (a draft, including one taken back or returned by the Moderator or the Dean)
    or still with the department."""
    return db.query(SAPProposal.event_id).filter(SAPProposal.seen_by_sds)


def scope_event_query(query, db, user):
    if user.role == "sds_staff":
        return query.filter(Event.id.in_(_sent_proposal_events(db)))
    if user.role == "signatory":
        return query.filter(Event.status == INSTITUTIONAL_REVIEW,
            db.query(DocumentRouting.id).filter(
                DocumentRouting.event_id == Event.id,
                DocumentRouting.review_round == Event.review_round,
                DocumentRouting.signatory_id == user.id,
            ).exists())
    return scope_query_by_department(query, Event.department_id, user)


def assert_event_read(db, event, user):
    if user.role == "sds_staff":
        if db.query(_sent_proposal_events(db).filter(SAPProposal.event_id == event.id).exists()).scalar():
            return
        raise HTTPException(403, "The SDS Office reads events once the Dean has approved their proposal")
    if user.role != "signatory":
        assert_record_scope(user, event, allow_officer_read=True)
        return
    assigned = db.query(DocumentRouting).filter(
        DocumentRouting.event_id == event.id, DocumentRouting.review_round == event.review_round,
        DocumentRouting.signatory_id == user.id,
    ).first()
    if event.status != INSTITUTIONAL_REVIEW or assigned is None:
        raise HTTPException(403, "Only assigned events pending institutional review are accessible")


def routing_steps(db, event):
    return db.query(DocumentRouting).filter(
        DocumentRouting.event_id == event.id, DocumentRouting.review_round == event.review_round,
    ).order_by(DocumentRouting.step_order).all()


def validate_signatories(db, event, signatory_ids):
    users = db.query(User).filter(User.id.in_(signatory_ids)).order_by(User.id).with_for_update().all()
    if len(users) != len(signatory_ids) or any(
        user.role != "signatory" or not user.is_active or user.is_suspended or user.must_change_password
        for user in users
    ):
        raise HTTPException(409, "Every assigned signatory must have an active, ready Signatory account")
    if event.proposed_by in signatory_ids:
        raise HTTPException(403, "An event proposer cannot be assigned to review their own event")


def begin_institutional_review(db, event):
    steps = routing_steps(db, event)
    if not steps:
        raise HTTPException(409, "Configure at least one institutional signatory before Admin approval"
                            if event.department_id is not None else
                            "Ask the Super Admin to assign institutional signatories to this event first")
    if any(step.status != "pending" for step in steps):
        raise HTTPException(409, "Institutional routing already contains decisions for this round")
    validate_signatories(db, event, [step.signatory_id for step in steps])
    require_pre_activity_clearance(db, event)
    event.status = INSTITUTIONAL_REVIEW


def review_institutional_step(db, event, user, decision, remarks):
    assert_event_read(db, event, user)
    assert_not_self_review(event.proposed_by, user)
    steps = routing_steps(db, event)
    current = next((step for step in steps if step.status != "approved"), None)
    if current is None or current.status != "pending" or current.signatory_id != user.id:
        raise HTTPException(409, "Only the next assigned signatory can review this event")
    if decision == "approved" and all(step is current or step.status == "approved" for step in steps):
        require_pre_activity_clearance(db, event)
    current.status = decision
    current.remarks = remarks
    current.decided_at = datetime.now(timezone.utc)
    record_decision(db, "event", event.id, decision, user, remarks)
    record_access_change(db, user, "event.institutional_reviewed", event, {
        "routing_id": str(current.id), "review_round": event.review_round,
        "step_order": current.step_order, "decision": decision,
    })
    if decision == "rejected":
        event.status = "rejected"
    elif all(step.status == "approved" for step in steps):
        event.status = "approved"


def restart_routing(db, event):
    previous = routing_steps(db, event)
    event.review_round += 1
    db.add_all([DocumentRouting(event_id=event.id, review_round=event.review_round,
        step_order=step.step_order, signatory_id=step.signatory_id) for step in previous])
