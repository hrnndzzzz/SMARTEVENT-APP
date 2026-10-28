"""Issue #9: proposal data and documented responses, using isolated fixtures."""
from io import BytesIO

import pytest
from pypdf import PdfReader
from pydantic import ValidationError

from app.test_sap import sap_system, fixture_data, populate, version
from app.test_access_management import system
from app.schemas_sap import Details, BudgetItem, validate_submission
from app.models_sap import SAPRevision
from app.services.sap_pdf import render_proposal
from app.main import app


@pytest.mark.parametrize('length', [1500, 4000])
def test_long_information_survives_submit_reload_and_pdf(sap_system, length):
    data = fixture_data()
    # Distinct boundary markers prove the entire addendum reaches the printout.
    info = 'BEGIN_INFO ' + ('Activity detail. ' * 250)[:length - 20] + ' END_INFO'
    assert len(info) == length
    data['details']['additional_information'] = info
    result = populate(sap_system, data)
    client, _, _, _, _, base = sap_system
    assert result['details']['additional_information'] == info
    assert client.get(base).json()['details']['additional_information'] == info
    response = client.get(base + '/pdf')
    assert response.status_code == 200
    text = ' '.join(line for page in PdfReader(BytesIO(response.content)).pages
                    for line in page.extract_text().splitlines()
                    # Page furniture: our stamp, and Word's footer (page number, form code).
                    if not line.startswith(('SAP revision ', 'Verify: ', 'SAS-SDS-FO-020'))
                    and not line.strip().isdigit())
    assert ' '.join(info.split()) in ' '.join(text.split())


def test_information_over_limit_rejected_by_draft_and_submission(sap_system):
    client, _, _, _, _, base = sap_system
    info = 'x' * 4001
    response = client.patch(base, json={'expected_version': version(client, base),
                                       'details': {'additional_information': info}})
    assert response.status_code == 422
    data = fixture_data()['details'] | {'additional_information': info}
    with pytest.raises(ValidationError):
        Details.model_validate(data)


def test_budget_quantity_and_cost_round_trip_without_recalculating_amount(sap_system):
    data = fixture_data()
    row = {'particulars': 'Snacks', 'quantity': 150, 'unit_cost': '10.00', 'amount': '2500.00'}
    data['collections']['budget-items'] = [row]
    result = populate(sap_system, data)
    client, db, _, _, _, base = sap_system
    assert result['collections']['budget-items'] == [row]
    assert client.get(base).json()['collections']['budget-items'] == [row]
    assert db.query(SAPRevision).one().snapshot['collections']['budget-items'] == [row]
    response = client.get(base + '/pdf')
    text = '\n'.join(p.extract_text() for p in PdfReader(BytesIO(response.content)).pages)
    for value in ('Particulars', 'Quantity', 'Unit cost', 'Amount', 'Snacks', '150', '10.00', '2500.00'):
        assert value in text
    # Display-only quantity/cost do not change the authoritative amount check.
    data['details']['total_budget'] = '1500.00'
    with pytest.raises(ValueError, match='exactly equal'):
        validate_submission(data['details'], data['collections'], data['clearance'])


def test_legacy_budget_defaults_and_printout():
    row = BudgetItem.model_validate({'particulars': 'Legacy', 'amount': '12.50'})
    assert row.quantity == 1 and row.unit_cost is None
    data = fixture_data()
    data['collections']['budget-items'] = [{'particulars': 'Legacy', 'amount': '12.50'}]
    text = '\n'.join(p.extract_text() for p in PdfReader(BytesIO(render_proposal(data, 'DRAFT'))).pages)
    text = text.rsplit('Budget breakdown', 1)[1]  # the form itself prints "( ) None"
    assert 'Legacy' in text and '12.50' in text and 'None' not in text


@pytest.mark.parametrize('quantity', [0, -1, 1.5, 100001, True])
def test_invalid_budget_quantity_rejected(quantity):
    with pytest.raises(ValidationError):
        BudgetItem.model_validate({'particulars': 'Snacks', 'amount': '1.00', 'quantity': quantity})


@pytest.mark.parametrize('cost', ['-0.01', '1.001', '10000000000.00', 'NaN', 'Infinity'])
def test_invalid_unit_cost_rejected(cost):
    with pytest.raises(ValidationError):
        BudgetItem.model_validate({'particulars': 'Snacks', 'amount': '1.00', 'unit_cost': cost})


def test_every_sap_success_response_has_a_schema():
    spec = app.openapi()
    checked = 0
    for path, operations in spec['paths'].items():
        for method, operation in operations.items():
            if not set(operation.get('tags', [])) & {'SAP', 'SAP verification'}:
                continue
            for status, response in operation['responses'].items():
                if not status.startswith('2'):
                    continue
                content = response.get('content', {})
                if path.endswith('/pdf'):
                    assert 'application/json' not in content
                    assert content['application/pdf']['schema'] == {'type': 'string', 'format': 'binary'}
                else:
                    assert content['application/json']['schema'], (method, path)
            checked += 1
    assert checked >= 20
    collections = spec['components']['schemas']['SAPCollectionsOut']['properties']
    assert set(collections) == {'budget-items', 'program-flow', 'support-requests', 'affected-classes'}


def test_response_schema_preserves_empty_draft_and_nested_money(sap_system):
    client, _, _, _, _, base = sap_system
    empty = client.get(base).json()
    assert empty['details'] == {}
    assert empty['clearance'] is None and empty['evaluation'] is None and empty['sds_review'] is None
    assert empty['collections']['budget-items'] == []
    result = populate(sap_system)
    assert isinstance(result['details']['total_budget'], str)
    assert isinstance(result['collections']['budget-items'][0]['amount'], str)
