"""The Moderator and the Dean review a sent proposal before the SDS Office does."""
from pathlib import Path

import pytest

from app.models import Approval, AuditLog, Notification, Organization
from app.models_sap import SAPProposal
from app.test_access_management import system
from app.test_sap import sap_system, send, populate, version, sign_current


@pytest.mark.parametrize('route', ['/return', '/revise'])
def test_an_sds_return_says_so_and_sending_again_clears_it(sap_system, route):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    if route == '/revise':
        sign_current(sap_system)
    login('sds_staff')
    returned = client.post(base + route, json={'expected_version': version(client, base), 'remarks': 'Fix the budget'})
    assert returned.status_code == 200, returned.text
    assert returned.json()['returned_by'] == 'sds'
    assert returned.json()['return_remarks'] == 'Fix the budget'
    login('treasurer')
    sent = client.post(base + '/submit', json={'expected_version': version(client, base)})
    assert sent.status_code == 200, sent.text
    assert sent.json()['returned_by'] is None and sent.json()['return_remarks'] is None


def test_department_review_migration():
    sql = (Path(__file__).parents[1] / 'supabase/migrations/20261030000100_sap_department_review.sql').read_text(encoding='utf-8')
    assert "'pending_department_review'" in sql
    assert "CHECK (returned_by IN ('moderator','dean','sds'))" in sql
    assert "UPDATE public.sap_proposals SET returned_by = 'sds' WHERE state = 'revision_requested'" in sql


@pytest.mark.parametrize('state,returned_by,seen', [
    ('draft', None, False),
    ('pending_department_review', None, False),
    ('revision_requested', 'moderator', False),
    ('revision_requested', 'dean', False),
    ('revision_requested', 'sds', True),
    ('pending_sap_review', None, True),
    ('sds_signed', None, True),
    ('rejected', None, True),
])
def test_the_sds_office_sees_a_proposal_once_it_reaches_the_office(sap_system, state, returned_by, seen):
    client, db, users, event, login, base = sap_system
    proposal = db.query(SAPProposal).one()
    proposal.state, proposal.returned_by = state, returned_by
    db.commit()
    login('sds_staff')
    assert (str(event.id) in [row['id'] for row in client.get('/events').json()]) is seen
    assert client.get(f'/events/{event.id}').status_code == (200 if seen else 403)
    assert client.get(base).status_code == (200 if seen else 403)


def decide(ctx, role, verdict, remarks=None):
    client, db, users, event, login, base = ctx
    login(role)
    return client.post(f'/events/{event.id}/{verdict}', json={} if remarks is None else {'remarks': remarks})


def test_sending_goes_to_the_moderator_first(sap_system):
    sent = send(sap_system)
    client, db, users, event, login, base = sap_system
    assert sent['state'] == 'pending_department_review' and event.status == 'pending_adviser'
    told = db.query(Notification).filter_by(kind='sap_workflow').all()
    assert [row.user_id for row in told] == [users['treasurer'].id]
    assert 'department review' in told[0].body
    login('sds_staff')
    assert client.get('/events').json() == []


@pytest.mark.parametrize('sender,creator', [('adviser', 'treasurer'), ('treasurer', 'adviser')])
def test_an_advisers_proposal_starts_with_the_dean(sap_system, sender, creator):
    client, db, users, event, login, base = sap_system
    event.proposed_by = users[creator].id
    db.commit()
    send(sap_system, proposer=sender)
    assert event.status == 'pending_admin'


@pytest.mark.parametrize('after_moderator', [False, True])
def test_withdrawing_during_department_review_tells_only_the_proposer(sap_system, after_moderator):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    if after_moderator:
        assert decide(sap_system, 'adviser', 'approve').status_code == 200
    login('treasurer')
    response = client.post(base + '/withdraw', json={'expected_version': version(client, base)})
    assert response.status_code == 200, response.text
    assert response.json()['state'] == 'draft' and event.status == 'draft'
    told = db.query(Notification).filter_by(title='SAP proposal withdrawn').all()
    assert [row.user_id for row in told] == [users['treasurer'].id]
    assert decide(sap_system, 'admin', 'approve').status_code == 409


def test_moderator_then_dean_send_it_to_the_sds_office(sap_system):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    first = decide(sap_system, 'adviser', 'approve', 'Looks fine')
    assert first.status_code == 200, first.text
    assert first.json()['status'] == 'pending_admin'
    assert db.query(SAPProposal).one().state == 'pending_department_review'
    second = decide(sap_system, 'admin', 'approve')
    assert second.status_code == 200, second.text
    assert second.json()['status'] == 'pending_institutional_review'
    assert db.query(SAPProposal).one().state == 'pending_sap_review'
    assert [(row.decision, row.reviewer_id) for row in db.query(Approval).order_by(Approval.step_order)] == [
        ('approved', users['adviser'].id), ('approved', users['admin'].id)]
    told = db.query(Notification).filter_by(title='SAP proposal sent to the SDS Office').all()
    assert {row.user_id for row in told} == {users['treasurer'].id, users['sds_staff'].id}
    login('sds_staff')
    assert client.get(base).status_code == 200


def test_the_moderators_approval_is_audited_and_tells_nobody(sap_system):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    told = db.query(Notification).count()
    assert decide(sap_system, 'adviser', 'approve').status_code == 200
    assert db.query(Notification).count() == told
    assert db.query(AuditLog).filter_by(action='sap_moderator_approved', entity_id=event.id).count() == 1


def test_a_super_admin_can_be_the_dean(sap_system):
    send(sap_system)
    assert decide(sap_system, 'adviser', 'approve').status_code == 200
    dean = decide(sap_system, 'super_admin', 'approve')
    assert dean.status_code == 200, dean.text
    assert dean.json()['status'] == 'pending_institutional_review'


def test_each_reviewer_waits_their_turn(sap_system):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    assert decide(sap_system, 'admin', 'approve').status_code == 409
    assert decide(sap_system, 'adviser', 'approve').status_code == 200
    assert decide(sap_system, 'adviser', 'approve').status_code == 409
    assert decide(sap_system, 'adviser', 'reject', 'Too late').status_code == 409
    assert db.query(Approval).count() == 1


@pytest.mark.parametrize('reviewer,after_moderator', [('adviser', False), ('admin', False), ('admin', True)])
def test_a_return_goes_back_to_the_draft_naming_who_sent_it(sap_system, reviewer, after_moderator):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    if after_moderator:
        assert decide(sap_system, 'adviser', 'approve').status_code == 200
    response = decide(sap_system, reviewer, 'reject', 'Move it to the afternoon')
    assert response.status_code == 200, response.text
    assert response.json()['status'] == 'draft'
    login('treasurer')
    proposal = client.get(base).json()
    assert proposal['state'] == 'revision_requested'
    assert proposal['return_remarks'] == 'Move it to the afternoon'
    assert proposal['returned_by'] == ('moderator' if reviewer == 'adviser' else 'dean')
    assert proposal['clearance'] is None
    told = db.query(Notification).filter_by(title='SAP proposal returned').all()
    assert [row.user_id for row in told] == [users['treasurer'].id]
    assert db.query(Approval).order_by(Approval.step_order.desc()).first().decision == 'returned'


@pytest.mark.parametrize('remarks', [None, '   '])
def test_a_return_needs_remarks(sap_system, remarks):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    assert decide(sap_system, 'adviser', 'reject', remarks).status_code == 422
    assert db.query(SAPProposal).one().state == 'pending_department_review'


@pytest.mark.parametrize('role', ['treasurer', 'officer', 'signatory', 'sds_staff'])
def test_only_the_moderator_or_dean_decide(sap_system, role):
    send(sap_system)
    for verdict in ('approve', 'reject'):
        assert decide(sap_system, role, verdict, 'No').status_code == 403


def test_a_moderator_from_another_organization_is_refused(sap_system):
    send(sap_system)
    client, db, users, event, login, base = sap_system
    users['adviser'].organization_id = db.query(Organization.id).filter_by(code='B').scalar()
    db.commit()
    assert decide(sap_system, 'adviser', 'approve').status_code == 403


def test_the_events_creator_cannot_review_it(sap_system):
    client, db, users, event, login, base = sap_system
    event.proposed_by = users['adviser'].id
    db.commit()
    send(sap_system)  # a colleague, the treasurer, sends it
    assert decide(sap_system, 'adviser', 'approve').status_code == 403


def test_a_proposal_past_department_review_is_refused_there(sap_system):
    populate(sap_system)
    refused = decide(sap_system, 'adviser', 'approve')
    assert refused.status_code == 409
    assert refused.json()['detail'] == 'This proposal is not waiting on department review'
