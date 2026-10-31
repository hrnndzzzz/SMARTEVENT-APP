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
    return '\n'.join(page.extract_text() for page in PdfReader(BytesIO(content)).pages)


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


@pytest.mark.parametrize('model,more', [(SDSReviewWrite, {'signature_strokes': [[{'x': 0.1, 'y': 0.2}]]}),
                                        (ReviewNotesWrite, {}), (DecisionWrite, {'remarks': 'Fix it'})])
def test_every_review_body_checks_section_remarks_the_same_way(model, more):
    assert model(expected_version=1, section_remarks={'budget': ' Meals ', 'other': ' '}, **more).section_remarks == {'budget': 'Meals'}
    for bad in ({'cafeteria': 'Meals'}, {'budget': 'x' * 1001}):
        with pytest.raises(ValidationError):
            model(expected_version=1, section_remarks=bad, **more)
