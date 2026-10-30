"""The Moderator and the Dean review a sent proposal before the SDS Office does."""
from pathlib import Path

import pytest

from app.models_sap import SAPProposal
from app.test_access_management import system
from app.test_sap import sap_system, populate, version, sign_current


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
