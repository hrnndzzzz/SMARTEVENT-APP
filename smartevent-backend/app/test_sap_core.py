"""Issue #9: proposal data and documented responses, using isolated fixtures."""
from io import BytesIO

import pytest
from pypdf import PdfReader
from pydantic import ValidationError

from app.test_sap import sap_system, fixture_data, populate, version
from app.test_access_management import system
from app.schemas_sap import Details


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
                    if not line.startswith(('SAP revision ', 'Verify: ')))
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
