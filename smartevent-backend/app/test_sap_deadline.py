"""Proposals nobody decided by 30 days before the activity are rejected by the system."""
from datetime import date

import pytest

from app.models import Approval, AuditLog, Notification
from app.models_sap import SAPProposal
from app.services.sap_deadline import REASON, reject_undecided_proposals
from app.test_access_management import system  # noqa: F401
from app.test_sap import sap_system, send, populate  # noqa: F401

ACTIVITY = date(2026, 10, 28)  # fixture_data()'s activity date


def proposal_of(db, event):
    return db.query(SAPProposal).filter_by(event_id=event.id).one()


def told(db):
    return {row.user_id for row in db.query(Notification).filter_by(title='SAP proposal rejected automatically')}


def test_one_still_with_the_department_29_days_out_is_rejected(sap_system):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    assert reject_undecided_proposals(db, today=date(2026, 9, 29)) == 1
    db.refresh(event)
    proposal = proposal_of(db, event)
    assert (proposal.state, event.status, proposal.return_remarks, proposal.returned_by) == (
        'rejected', 'rejected', REASON, None)
    decision = db.query(Approval).filter_by(entity_id=event.id, decision='rejected').one()
    assert decision.reviewer_id is None and decision.remarks == REASON
    assert db.query(AuditLog).filter_by(action='sap_auto_rejected', user_id=None).count() == 1
    assert users['treasurer'].id in told(db) and users['sds_staff'].id not in told(db)
    login('treasurer')
    shown = client.get(base).json()
    assert (shown['state'], shown['return_remarks'], shown['returned_by']) == ('rejected', REASON, None)
    assert reject_undecided_proposals(db, today=date(2026, 9, 29)) == 0  # already done


def test_one_still_with_the_sds_office_is_rejected_and_the_office_told(sap_system):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    assert proposal_of(db, event).state == 'pending_sap_review'
    assert reject_undecided_proposals(db, today=date(2026, 10, 20)) == 1
    assert {users['treasurer'].id, users['sds_staff'].id} <= told(db)
    login('treasurer')
    history = client.get(f'/events/{event.id}/approvals').json()
    assert (history[-1]['decision'], history[-1]['reviewer_id'], history[-1]['remarks']) == ('rejected', None, REASON)


@pytest.mark.parametrize('state,today', [
    ('pending_department_review', date(2026, 9, 28)),  # exactly 30 days: the last day it could be sent
    ('draft', date(2026, 10, 20)),
    ('revision_requested', date(2026, 10, 20)),  # waiting on the proposer, not an approver
    ('sds_signed', date(2026, 10, 20)),  # the SDS Office has decided
])
def test_a_proposal_not_waiting_past_the_line_is_left_alone(sap_system, state, today):
    client, db, users, event, login, base = sap_system
    proposal = proposal_of(db, event)
    proposal.state, event.event_date = state, ACTIVITY
    db.commit()
    assert reject_undecided_proposals(db, today=today) == 0
    db.refresh(proposal)
    assert proposal.state == state and not told(db)


def test_the_server_starts_the_deadline_check(monkeypatch):
    from fastapi.testclient import TestClient
    from app.main import app

    started = []
    monkeypatch.setattr("app.services.sap_deadline.start_deadline_check", lambda factory: started.append(factory))
    with TestClient(app):
        pass
    assert len(started) == 1
