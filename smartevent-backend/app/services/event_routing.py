"""Who may read which events; never grants operational access.

Until the November defence this file also ran institutional review: a
`document_routing` row per signatory, each signing in turn after the Dean.
The signatory role is gone — those people sign the printed Student Activity
Proposal instead — so the Dean's approval is now the last one, and what is
left here is the read scope for the SDS Office.

`pending_institutional_review` survives the removal. Two paths set it and
only one of them was the signatories': `services/sap.py` puts an event there
through `send_to_sds` when the Dean approves a proposal, which is the SDS
Office's queue and nothing to do with routing.
"""

from fastapi import HTTPException

from app.dependencies import assert_record_scope, require_role, scope_query_by_department
from app.models import Event
from app.models_sap import SAPProposal

INSTITUTIONAL_REVIEW = "pending_institutional_review"
require_event_reader = require_role("admin", "adviser", "officer", "sds_staff")


def _sent_proposal_events(db):
    """Events whose SAP proposal has reached the SDS Office: its work. Until then it is the
    proposer's (a draft, including one taken back or returned by the Moderator or the Dean)
    or still with the department."""
    return db.query(SAPProposal.event_id).filter(SAPProposal.seen_by_sds)


def scope_event_query(query, db, user):
    if user.role == "sds_staff":
        return query.filter(Event.id.in_(_sent_proposal_events(db)))
    return scope_query_by_department(query, Event.department_id, user)


def assert_event_read(db, event, user):
    if user.role == "sds_staff":
        if db.query(_sent_proposal_events(db).filter(SAPProposal.event_id == event.id).exists()).scalar():
            return
        raise HTTPException(403, "The SDS Office reads events once the Dean has approved their proposal")
    assert_record_scope(user, event, allow_officer_read=True)
