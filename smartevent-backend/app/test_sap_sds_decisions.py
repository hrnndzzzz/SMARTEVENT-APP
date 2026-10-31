"""The SDS Office's three decisions, their remarks, and what follows."""
from io import BytesIO

import pytest
from pydantic import ValidationError
from pypdf import PdfReader

from app.models import Notification
from app.models_sap import SAPProposal, SAPRevision
from app.schemas_sap import DecisionWrite, ReviewNotesWrite, SDSReviewWrite
from app.test_access_management import system
from app.test_sap import sap_system, populate, version, checkpoint, sign_current, fixture_data, send, department_approves


def pdf_text(content):
    """The printed text on one line: Word wraps a remark inside the SDS cell, which is narrow."""
    return ' '.join(' '.join(page.extract_text() for page in PdfReader(BytesIO(content)).pages).split())


@pytest.mark.parametrize('sent,kept', [(None, {'budget': 'Meals over the allowance'}),
                                       ({'other': 'Attach the venue letter'}, {'other': 'Attach the venue letter'})])
def test_a_return_keeps_section_remarks_and_prints_them(sap_system, sent, kept):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    login('sds_staff')
    assert client.put(base + '/sds-review', json={'expected_version': version(client, base), 'overall_remarks': 'Draft note',
                                                  'section_remarks': {'budget': 'Meals over the allowance'}}).status_code == 200
    body = {'expected_version': version(client, base), 'remarks': 'Fix the budget'}
    if sent is not None:
        body['section_remarks'] = sent
    returned = client.post(base + '/return', json=body)
    assert returned.status_code == 200, returned.text
    assert returned.json()['sds_review']['overall_remarks'] == 'Fix the budget'
    assert returned.json()['sds_review']['section_remarks'] == kept
    text = pdf_text(client.get(base + '/pdf').content)
    assert 'SDS: Fix the budget' in text
    for remark in kept.values():
        assert remark in text


@pytest.mark.parametrize('model,more', [(SDSReviewWrite, {'signature_strokes': [[{'x': 0.1, 'y': 0.2}]]}),
                                        (ReviewNotesWrite, {}), (DecisionWrite, {'remarks': 'Fix it'})])
def test_every_review_body_checks_section_remarks_the_same_way(model, more):
    assert model(expected_version=1, section_remarks={'budget': ' Meals ', 'other': ' '}, **more).section_remarks == {'budget': 'Meals'}
    for bad in ({'cafeteria': 'Meals'}, {'budget': 'x' * 1001}):
        with pytest.raises(ValidationError):
            model(expected_version=1, section_remarks=bad, **more)


def test_the_sds_office_rejects_with_remarks_and_the_form_says_so(sap_system):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    login('sds_staff')
    response = client.post(base + '/sds-reject', json={'expected_version': version(client, base), 'remarks': 'Not an organizational activity'})
    assert response.status_code == 200, response.text
    assert response.json()['state'] == 'rejected' and event.status == 'rejected'
    assert response.json()['sds_review']['overall_remarks'] == 'Not an organizational activity'
    assert response.json()['returned_by'] is None
    text = pdf_text(client.get(base + '/pdf').content)
    assert 'REJECTED BY THE SDS OFFICE' in text and 'SDS: Not an organizational activity' in text
    assert 'SAP revision 1 | Rejected by SDS' in text
    token = db.query(SAPRevision).one().verification_token
    assert client.get('/sap/verify/' + token).json()['approval_state'] == 'rejected'
    told = db.query(Notification).filter_by(title='SAP proposal rejected').all()
    assert users['treasurer'].id in {row.user_id for row in told}


@pytest.mark.parametrize('remarks', ['', '   '])
def test_a_rejection_needs_remarks(sap_system, remarks):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    login('sds_staff')
    assert client.post(base + '/sds-reject', json={'expected_version': version(client, base), 'remarks': remarks}).status_code == 422


@pytest.mark.parametrize('role', ['treasurer', 'adviser', 'admin', 'super_admin', 'officer', 'signatory'])
def test_only_the_sds_office_can_reject(sap_system, monkeypatch, role):
    monkeypatch.setattr('app.services.sap.render_proposal', lambda *args, **kwargs: b'%PDF-1.4 submitted')
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    current = version(client, base)
    login(role)
    assert client.post(base + '/sds-reject', json={'expected_version': current, 'remarks': 'No'}).status_code == 403
    assert db.query(SAPProposal).one().state == 'pending_sap_review'


STROKES = [[{'x': 0.1, 'y': 0.2}, {'x': 0.8, 'y': 0.7}]]
LATE_WRITES = [
    ('treasurer', 'patch', '', {'details': {'title': 'Changed'}}),
    ('treasurer', 'post', '/submit', {}),
    ('treasurer', 'post', '/withdraw', {}),
    ('sds_staff', 'put', '/sds-review', {'overall_remarks': 'Late'}),
    ('sds_staff', 'post', '/sds-sign', {'signature_strokes': STROKES}),
    ('sds_staff', 'put', '/sds-clearance', {'clearance': fixture_data()['clearance']}),
    ('sds_staff', 'post', '/return', {'remarks': 'Again'}),
    ('sds_staff', 'post', '/sds-reject', {'remarks': 'Again'}),
    ('sds_staff', 'post', '/revise', {'remarks': 'Again'}),
]


@pytest.mark.parametrize('role,method,path,body', LATE_WRITES)
def test_a_rejected_proposal_is_final(sap_system, role, method, path, body):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    login('sds_staff')
    assert client.post(base + '/sds-reject', json={'expected_version': version(client, base), 'remarks': 'No'}).status_code == 200
    login(role)
    response = client.request(method.upper(), base + path, json={'expected_version': version(client, base), **body})
    assert response.status_code == 409, response.text
    assert checkpoint(sap_system, 1).status_code == 409
    login('adviser')
    assert client.post(f'/events/{event.id}/approve', json={}).status_code == 409
    assert db.query(SAPProposal).one().state == 'rejected'


def test_only_the_current_revision_of_a_rejected_proposal_prints_rejected(sap_system, monkeypatch):
    marks = {}  # revision number -> the rejected flag /pdf rendered it with; the renders themselves are stubbed
    monkeypatch.setattr('app.services.sap.render_proposal', lambda *args, **kwargs: b'%PDF-1.4 submitted')
    monkeypatch.setattr('app.routers.sap.render_proposal', lambda *args, **kwargs: marks.update({args[1]: kwargs.get('rejected', False)}) or b'%PDF-1.4 rendered')
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    login('sds_staff')
    assert client.post(base + '/return', json={'expected_version': version(client, base), 'remarks': 'Fix it'}).status_code == 200
    populate(sap_system)
    login('sds_staff')
    assert client.post(base + '/sds-reject', json={'expected_version': version(client, base), 'remarks': 'No'}).status_code == 200
    assert client.get(base + '/pdf?revision_no=1').status_code == 200
    assert client.get(base + '/pdf').status_code == 200
    assert marks == {1: False, 2: True}


def test_slots_five_to_nine_wait_for_the_sds_signature(sap_system):
    populate(sap_system)
    client, db, users, event, login, base = sap_system
    for slot in (1, 3, 2, 4):
        assert checkpoint(sap_system, slot).status_code == 200
    assert client.get(base + '/workflow').json()['steps'][4]['actionable'] is False
    early = checkpoint(sap_system, 5)
    assert early.status_code == 409 and early.json()['detail'] == 'Slots 5 to 9 are signed after the SDS Office signs'
    sign_current(sap_system)
    assert client.get(base + '/workflow').json()['steps'][4]['actionable'] is True
    assert checkpoint(sap_system, 5).status_code == 200
