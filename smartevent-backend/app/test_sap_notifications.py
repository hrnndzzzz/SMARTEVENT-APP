"""SAP inbox payloads and existing email retries, without real external delivery."""
import base64

import pytest

from app.test_access_management import system
from app.test_sap import sap_system, populate, version
from app.models import Notification
from app.models_sap import SAPProposal
from app.services import sap
from app.services.notifications import deliver_notification


@pytest.mark.parametrize('action,state,phrase,sds_hears', [
    ('sap_submitted', 'pending_department_review', 'department review', False),
    ('sap_returned', 'revision_requested', 'returned for changes', True),
    ('sap_signed_revision_correction_requested', 'revision_requested', 'returned for changes', True),
    ('sap_revision_signed', 'sds_signed', 'signed', True),
    ('sap_approved_with_physical_evidence', 'approved', 'approved', True),
    ('sap_evaluated', 'completed', 'evaluation', True),
    ('sap_withdrawn', 'draft', 'withdrawn', True),
    ('sap_checkpoint_recorded', 'pending_sap_review', 'checkpoint', True),
    ('sap_dean_approved', 'pending_sap_review', 'now with the SDS Office', True),
    ('sap_department_returned', 'revision_requested', 'returned for changes', False),
    ('sap_rejected', 'rejected', 'rejected', True),
])
def test_sap_notification_payload_wording_and_recipients(sap_system, action, state, phrase, sds_hears):
    client, db, users, event, _, base = sap_system
    proposal = db.query(SAPProposal).one()
    proposal.state = state
    sap.save(db, event, proposal, users['treasurer'], action, notify=True, notify_sds=sds_hears)
    rows = db.query(Notification).filter_by(kind='sap_workflow').all()
    assert {row.user_id for row in rows} == {users['treasurer'].id} | ({users['sds_staff'].id} if sds_hears else set())
    expected = {'event_id': str(event.id), 'proposal_id': str(proposal.id),
                'revision_no': proposal.revision_no, 'state': state, 'action': action}
    for row in rows:
        assert row.payload == expected
        assert event.title in row.body and phrase in row.body
        assert row.email_status == 'pending'
        if state == 'sds_signed':
            assert 'approved' not in row.title.lower() + row.body.lower()
    response = client.get('/notifications')
    assert response.status_code == 200
    assert response.json()[0]['payload'] == expected


def test_legacy_notifications_have_null_payload_and_remain_private(sap_system):
    client, db, users, _, login, _ = sap_system
    old = Notification(user_id=users['treasurer'].id, kind='old', title='Old', body='Legacy record', email_status='sent')
    db.add(old)
    db.commit()
    inbox = client.get('/notifications').json()
    assert inbox[0]['payload'] is None
    login('sds_staff')
    assert client.get('/notifications').json() == []
    assert client.patch(f'/notifications/{old.id}/read').status_code == 404


def test_sds_gets_the_filled_form_by_email_when_the_dean_approves(sap_system, monkeypatch):
    client, db, users, *_ = sap_system
    sent = []
    monkeypatch.setattr('app.services.notifications.send_email',
                        lambda to, subject, body, **kw: sent.append((to, subject, kw.get('attachments'))))
    populate(sap_system)
    sds = [s for s in sent if s[0] == users['sds_staff'].email and s[1] == 'SAP proposal sent to the SDS Office']
    assert len(sds) == 1 and len(sds[0][2]) == 1
    assert base64.b64decode(sds[0][2][0]['content']).startswith(b'%PDF')
    assert sds[0][2][0]['filename'] == 'SAP-revision-1.pdf'
    assert all(s[2] is None for s in sent if s[0] != users['sds_staff'].email)
    row = db.query(Notification).filter_by(user_id=users['sds_staff'].id, title='SAP proposal sent to the SDS Office').one()
    assert row.email_status == 'sent'


def test_failed_email_retry_keeps_workflow_and_does_not_resend_sent(sap_system, monkeypatch):
    submitted = populate(sap_system)
    client, db, users, _, _, base = sap_system
    notification = db.query(Notification).filter_by(user_id=users['treasurer'].id, title='SAP proposal submitted').one()
    payload = dict(notification.payload)
    def fail(*args, **kwargs):
        raise RuntimeError('mail provider unavailable')
    monkeypatch.setattr('app.services.notifications.send_email', fail)
    deliver_notification(db, notification.id)
    assert notification.email_status == 'failed' and notification.email_attempts == 1
    assert client.get(base).json()['state'] == submitted['state'] == 'pending_sap_review'
    messages = []
    monkeypatch.setattr('app.services.notifications.send_email', lambda *args, **kwargs: messages.append((args, kwargs)))
    deliver_notification(db, notification.id)
    deliver_notification(db, notification.id)
    assert notification.email_status == 'sent' and notification.email_attempts == 2
    assert len(messages) == 1 and messages[0][1]['idempotency_key'] == f'sap_workflow/{notification.id}'
    assert notification.payload == payload
