"""Withdrawal preserves submitted evidence and rejects review races."""
from copy import deepcopy

import pytest
from sqlalchemy.exc import SQLAlchemyError

from app.test_access_management import system
from app.test_sap import sap_system, populate, version, checkpoint, sign_current, fixture_data
from app.models import Notification, AuditLog
from app.models_sap import SAPAttachment, SAPCheckpoint, SAPProposal, SAPRevision, SAPReview


def test_withdraw_preserves_history_and_carries_attachments_into_resubmission(sap_system):
    client, db, users, event, login, base = sap_system
    attachment = SAPAttachment(proposal_id=db.query(SAPProposal).one().id, revision_no=1,
        category='appendix', display_name='Budget.pdf', file_name='Budget.pdf',
        content_type='application/pdf', storage_ref='private/test-budget.pdf', sha256='a' * 64,
        uploaded_by=users['treasurer'].id)
    db.add(attachment)
    db.commit()
    submitted = populate(sap_system)
    rev = db.query(SAPRevision).one()
    saved = (deepcopy(rev.snapshot), rev.printable_pdf, rev.pdf_sha256, rev.verification_token)
    checkpoint_ids = [row.id for row in db.query(SAPCheckpoint).all()]
    response = client.post(base + '/withdraw', json={'expected_version': submitted['version']})
    assert response.status_code == 200, response.text
    result = response.json()
    assert result['state'] == 'draft' and event.status == 'draft'
    assert result['version'] == submitted['version'] + 1 and result['revision_no'] == 1
    assert result['clearance'] is None
    assert len(result['attachments']) == 1
    assert result['attachments'][0]['id'] != str(attachment.id)
    assert client.get(base + '/attachments', params={'revision_no': 1}).json()[0]['id'] == str(attachment.id)
    copies = db.query(SAPAttachment).order_by(SAPAttachment.revision_no).all()
    assert [x.revision_no for x in copies] == [1, 2]
    assert copies[0].storage_ref == copies[1].storage_ref
    assert copies[0].uploaded_by == copies[1].uploaded_by
    assert copies[0].uploaded_at == copies[1].uploaded_at
    assert db.query(Notification).filter_by(kind='sap_workflow').count() == 4
    # The old Part 4 does not carry over: the SDS Office fills a fresh one
    # while reviewing the resubmission, before it can sign (see test_sap).
    resubmitted = client.post(base + '/submit', json={'expected_version': version(client, base)})
    assert resubmitted.status_code == 200, resubmitted.text
    assert resubmitted.json()['revision_no'] == 2
    assert resubmitted.json()['clearance'] is None
    assert len(resubmitted.json()['attachments']) == 1
    db.refresh(rev)
    assert (rev.snapshot, rev.printable_pdf, rev.pdf_sha256, rev.verification_token) == saved
    assert all(db.get(SAPCheckpoint, key) is not None for key in checkpoint_ids)
    assert client.get(base + '/workflow').json()['completed_count'] == 0
    assert client.get('/sap/verify/' + rev.verification_token).json()['approval_state'] == 'superseded'


@pytest.mark.parametrize('role', ['adviser', 'admin', 'super_admin', 'officer', 'signatory', 'sds_staff'])
def test_nonproposer_cannot_withdraw(sap_system, role):
    submitted = populate(sap_system)
    client, _, _, _, login, base = sap_system
    login(role)
    assert client.post(base + '/withdraw', json={'expected_version': submitted['version']}).status_code == 403


@pytest.mark.parametrize('review', ['empty_notes', 'notes', 'checkpoint', 'signature'])
def test_any_sds_review_blocks_withdrawal(sap_system, review):
    populate(sap_system)
    client, _, _, _, login, base = sap_system
    login('sds_staff')
    if review in {'notes', 'empty_notes'}:
        assert client.put(base + '/sds-review', json={'expected_version': version(client, base),
            'overall_remarks': 'Check the venue' if review == 'notes' else ''}).status_code == 200
    elif review == 'checkpoint':
        assert checkpoint(sap_system, 1).status_code == 200
    else:
        sign_current(sap_system)
    login('treasurer')
    assert client.post(base + '/withdraw', json={'expected_version': version(client, base)}).status_code == 409


@pytest.mark.parametrize('state', ['draft', 'revision_requested', 'sds_signed', 'approved', 'completed', 'rejected'])
def test_only_pending_state_can_be_withdrawn(sap_system, state):
    populate(sap_system)
    client, db, _, _, _, base = sap_system
    db.query(SAPProposal).one().state = state
    db.commit()
    assert client.post(base + '/withdraw', json={'expected_version': version(client, base)}).status_code == 409


def test_stale_withdrawal_and_review_after_withdrawal_are_rejected(sap_system):
    submitted = populate(sap_system)
    client, db, _, _, login, base = sap_system
    assert client.post(base + '/withdraw', json={'expected_version': submitted['version'] - 1}).status_code == 409
    assert client.post(base + '/withdraw', json={'expected_version': submitted['version']}).status_code == 200
    login('sds_staff')
    for expected in (submitted['version'], version(client, base)):
        assert client.put(base + '/sds-review', json={'expected_version': expected, 'overall_remarks': 'Late review'}).status_code == 409
    assert db.query(SAPReview).count() == 0


def test_failed_withdrawal_commit_leaves_no_state_audit_or_notification(sap_system, monkeypatch):
    submitted = populate(sap_system)
    client, db, _, event, _, base = sap_system
    before = (db.query(Notification).count(), db.query(AuditLog).count(), db.query(SAPAttachment).count())
    def failed_commit():
        db.rollback()
        raise SQLAlchemyError('injected transaction failure')
    monkeypatch.setattr(db, 'commit', failed_commit)
    response = client.post(base + '/withdraw', json={'expected_version': submitted['version']})
    assert response.status_code == 503
    db.expire_all()
    assert db.query(SAPProposal).one().state == 'pending_sap_review'
    assert event.status == 'pending_institutional_review'
    assert (db.query(Notification).count(), db.query(AuditLog).count(), db.query(SAPAttachment).count()) == before
