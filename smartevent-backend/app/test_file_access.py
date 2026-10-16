"""Private file links require role, scope, and an authorized record or new upload."""

from datetime import date
from uuid import uuid4

import httpx
import pytest

from app.config import settings
from app.models import EventProposalLetter, Receipt
from app.services.storage import StorageError, canonical_file_url
from app.test_access_management import system


@pytest.fixture
def signer(monkeypatch):
    monkeypatch.setattr(settings, "supabase_url", "https://storage.example.com")
    monkeypatch.setattr(settings, "supabase_service_key", "fake-key")
    calls = []
    def sign(reference, bucket):
        calls.append((reference, bucket))
        return reference + "?token=temporary"
    monkeypatch.setattr("app.routers.files.signed_file_url", sign)
    monkeypatch.setattr(httpx, "request", lambda *a, **k: pytest.fail("Unexpected external request"))
    return calls


def reference(bucket, *path):
    return f"{settings.supabase_url}/storage/v1/object/{bucket}/" + "/".join(map(str, path))


def access(client, url):
    return client.get("/files", params={"reference": url})


@pytest.mark.parametrize("role", ["treasurer", "admin", "super_admin"])
def test_financial_writers_can_read_own_new_organization_upload(system, signer, role):
    client, db, users, orgs, resources, login = system
    login(role)
    url = reference("receipts", orgs[0].id, users[role].id, str(uuid4()) + ".jpg")
    response = access(client, url + "?token=obsolete")
    assert response.status_code == 200, response.text
    assert response.json() == {"url": url + "?token=temporary", "expires_in": 300}
    assert signer == [(url, "receipts")]
    assert response.headers["cache-control"] == "no-store"


@pytest.mark.parametrize("role", ["officer", "adviser", "sds_staff"])
def test_other_roles_cannot_read_unattached_uploads(system, signer, role):
    client, db, users, orgs, resources, login = system
    login(role)
    url = reference("receipts", orgs[0].id, users[role].id, str(uuid4()) + ".jpg")
    assert access(client, url).status_code in (403, 404)
    assert signer == []


def test_upload_reference_cannot_follow_user_after_transfer(system, signer):
    client, db, users, orgs, resources, login = system
    user = users["treasurer"]
    url = reference("receipts", orgs[0].id, user.id, str(uuid4()) + ".jpg")
    user.organization_id = orgs[1].id
    db.commit()
    login("treasurer")
    assert access(client, url).status_code == 404
    assert signer == []


@pytest.mark.parametrize("model", ["receipt", "expense"])
@pytest.mark.parametrize("role", ["officer", "adviser", "treasurer", "admin", "super_admin"])
def test_recorded_receipts_authorize_other_uploaders_and_legacy_forms(system, signer, model, role):
    client, db, users, orgs, resources, login = system
    filename = str(uuid4()) + ".jpg"
    url = reference("receipts", users["adviser"].id, filename)
    stored_url = url.replace("/object/", "/object/public/")
    if model == "expense":
        resources[0]["expenses"].receipt_url = stored_url
    else:
        db.add(Receipt(
            organization_id=orgs[0].id, department_id=orgs[0].department_id,
            event_id=resources[0]["events"].id, income_id=resources[0]["incomes"].id,
            purpose="Evidence", receipt_url=stored_url, issued_on=date.today(), amount=100,
            url_fingerprint=uuid4().hex, recorded_by=users["treasurer"].id,
        ))
    db.commit()
    login(role)
    signed_reference = url.replace("/object/", "/object/sign/") + "?token=old-secret"
    response = access(client, signed_reference)
    assert response.status_code == 200, response.text
    assert signer == [(url, "receipts")]


def test_recorded_reference_is_not_disclosed_to_foreign_organization(system, signer):
    client, db, users, orgs, resources, login = system
    url = reference("receipts", users["adviser"].id, str(uuid4()) + ".jpg")
    resources[1]["expenses"].receipt_url = url
    db.commit()
    login("officer")
    response = access(client, url)
    absent = access(client, reference("receipts", users["adviser"].id, str(uuid4()) + ".jpg"))
    assert response.status_code == absent.status_code == 404
    assert response.json() == absent.json()
    assert signer == []


def add_proposal(db, resources, users, index, url):
    db.add(EventProposalLetter(
        event_id=resources[index]["events"].id, title="Proposal", document_url=url,
        submitted_by=users["adviser"].id,
    ))
    db.commit()


@pytest.mark.parametrize("role", ["adviser", "treasurer", "admin", "sds_staff", "super_admin"])
def test_proposals_need_record_access_and_support_sds_global_reads(system, signer, role):
    client, db, users, orgs, resources, login = system
    index = 1 if role in {"sds_staff", "super_admin"} else 0
    url = reference("proposal-letters", orgs[index].id, users["adviser"].id, str(uuid4()) + ".pdf")
    add_proposal(db, resources, users, index, url.replace("/object/", "/object/authenticated/"))
    login(role)
    assert access(client, url).status_code == 200
    assert signer == [(url, "proposal-letters")]


def test_proposal_writers_cannot_sign_arbitrary_or_foreign_records(system, signer):
    client, db, users, orgs, resources, login = system
    foreign = reference("proposal-letters", orgs[1].id, users["treasurer"].id, str(uuid4()) + ".pdf")
    add_proposal(db, resources, users, 1, foreign)
    login("treasurer")
    assert access(client, foreign).status_code == 404
    own_unattached = reference("proposal-letters", orgs[0].id, users["treasurer"].id, str(uuid4()) + ".pdf")
    assert access(client, own_unattached).status_code == 404
    login("officer")
    assert access(client, foreign).status_code == 403
    assert signer == []


@pytest.mark.parametrize("url", [
    "https://evil.example/storage/v1/object/receipts/file.jpg",
    "https://storage.example.com.attacker.test/storage/v1/object/receipts/file.jpg",
    "https://storage.example.com/storage/v1/object/other/file.jpg",
    "https://storage.example.com/storage/v1/object/receipts/%2e%2e/file.jpg",
])
def test_untrusted_references_are_rejected_before_signing(system, signer, url):
    client, db, users, orgs, resources, login = system
    login("super_admin")
    assert access(client, url).status_code == 422
    assert signer == []


def test_file_access_requires_authenticated_ready_account(system, signer):
    client, db, users, orgs, resources, login = system
    url = reference("receipts", orgs[0].id, users["treasurer"].id, str(uuid4()) + ".jpg")
    assert access(client, url).status_code == 401
    login("treasurer")
    users["treasurer"].must_change_password = True
    db.commit()
    assert access(client, url).status_code == 403
    assert signer == []


def test_legacy_filename_wildcards_are_literal_and_canonical_forms_match(system, signer):
    client, db, users, orgs, resources, login = system
    url = reference("receipts", users["adviser"].id, "receipt%25_1.jpg")
    resources[0]["expenses"].receipt_url = url.replace("/object/", "/object/public/")
    db.commit()
    login("officer")
    response = access(client, url)
    assert response.status_code == 200
    assert signer == [(canonical_file_url(url), "receipts")]


@pytest.mark.parametrize("error,status", [(StorageError("private provider details"), 502),
                                           (RuntimeError("private API key"), 503)])
def test_file_signing_failures_are_sanitized(system, signer, monkeypatch, error, status):
    client, db, users, orgs, resources, login = system
    url = reference("receipts", orgs[0].id, users["treasurer"].id, str(uuid4()) + ".jpg")
    def fail(*args):
        raise error
    monkeypatch.setattr("app.routers.files.signed_file_url", fail)
    login("treasurer")
    response = access(client, url)
    assert response.status_code == status and "private" not in response.text


def test_record_lists_return_references_without_contacting_storage(system, signer):
    client, db, users, orgs, resources, login = system
    receipt_url = reference("receipts", orgs[0].id, users["treasurer"].id, str(uuid4()) + ".jpg")
    proposal_url = reference("proposal-letters", orgs[0].id, users["adviser"].id, str(uuid4()) + ".pdf")
    resources[0]["expenses"].receipt_url = receipt_url
    add_proposal(db, resources, users, 0, proposal_url)
    login("admin")
    assert client.get("/expenses").json()[0]["receipt_url"] == receipt_url
    assert client.get("/proposal-letters").json()[0]["document_url"] == proposal_url
    assert signer == []
