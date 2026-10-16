import io
from datetime import date
from uuid import uuid4

import httpx
import pytest
from PIL import Image

from app.config import settings
from app.models import Receipt
from app.services import ocr, storage
from app.services.receipt_validation import fingerprint, url_key
from app.test_access_management import system


@pytest.fixture
def private_storage(monkeypatch):
    monkeypatch.setattr(settings, "supabase_url", "https://storage.example.com")
    monkeypatch.setattr(settings, "supabase_service_key", "server-only-key")
    requests = []

    def request(method, url, **kwargs):
        requests.append((method, url, kwargs))
        payload = {"public": False}
        if "/object/sign/" in url:
            payload = {"signedURL": url.removeprefix(settings.supabase_url + "/storage/v1") + "?token=temporary"}
        return httpx.Response(200, json=payload, request=httpx.Request(method, url))

    monkeypatch.setattr(httpx, "request", request)
    return requests


def image_bytes(size=(16, 16)):
    buffer = io.BytesIO()
    Image.new("RGBA", size, "red").save(buffer, format="PNG")
    return buffer.getvalue()


def test_images_are_verified_resized_and_stripped_of_metadata(monkeypatch):
    buffer = io.BytesIO()
    exif = Image.Exif()
    exif[0x010E] = "Private camera metadata"
    Image.new("RGB", (2400, 20), "red").save(buffer, format="JPEG", exif=exif)
    raw = buffer.getvalue()
    processed, mime = storage.prepare_image_for_upload(raw)
    with Image.open(io.BytesIO(processed)) as image:
        assert mime == "image/jpeg" and image.mode == "RGB"
        assert max(image.size) <= 1800 and not image.getexif()
    monkeypatch.setattr(storage, "MAX_IMAGE_PIXELS", 100)
    with pytest.raises(ValueError, match="resolution"):
        storage.prepare_image_for_upload(raw)
    for data in (b"", b"not an image", b"x" * (storage.MAX_UPLOAD_BYTES + 1)):
        with pytest.raises(Exception):
            storage.prepare_image_for_upload(data)


def test_uploads_require_private_buckets_and_use_uploader_paths(private_storage, monkeypatch):
    owner, organization = uuid4(), uuid4()
    url = storage.upload_receipt_image(b"prepared", "image/jpeg", owner, organization)
    assert url.startswith(f"{settings.supabase_url}/storage/v1/object/receipts/{organization}/{owner}/")
    assert "/public/" not in url and "token=" not in url
    assert [request[0] for request in private_storage] == ["GET", "POST"]
    assert private_storage[-1][2]["headers"]["x-upsert"] == "false"

    def public_bucket(method, url, **kwargs):
        return httpx.Response(200, json={"public": True}, request=httpx.Request(method, url))

    monkeypatch.setattr(httpx, "request", public_bucket)
    with pytest.raises(storage.StorageError, match="must be private"):
        storage.upload_receipt_image(b"prepared", "image/jpeg", owner, organization)


def test_signed_urls_canonicalize_and_cannot_sign_other_buckets_or_hosts(private_storage):
    path = f"receipts/{uuid4()}/{uuid4()}.jpg"
    base = settings.supabase_url + "/storage/v1/object/"
    variants = [base + path, base + "public/" + path, base + "authenticated/" + path,
                base + "sign/" + path + "?token=old"]
    assert len({url_key(url) for url in variants}) == 1
    signed = storage.signed_file_url(variants[0], settings.supabase_receipts_bucket)
    assert signed.endswith("?token=temporary")
    assert private_storage[-1][2]["json"] == {"expiresIn": 300}
    assert storage.canonical_file_url(signed) == variants[0]
    before = len(private_storage)
    external = "https://storage.example.com.attacker.test/storage/v1/object/receipts/file.jpg"
    assert storage.signed_file_url(external) == external
    assert len(private_storage) == before
    for invalid in (base + "other/file.jpg", base + "receipts/%2E%2E/file.jpg",
                    base + "proposal-letters/file.pdf"):
        with pytest.raises(ValueError):
            storage.signed_file_url(invalid, settings.supabase_receipts_bucket)
    assert len(private_storage) == before


def test_storage_errors_do_not_disclose_provider_details(private_storage, monkeypatch):
    def error(method, url, **kwargs):
        return httpx.Response(500, text="server-only-key and database information",
                              request=httpx.Request(method, url))

    monkeypatch.setattr(httpx, "request", error)
    with pytest.raises(storage.StorageError) as exc:
        storage.upload_receipt_image(b"prepared", "image/jpeg", uuid4(), uuid4())
    assert "server-only-key" not in str(exc.value) and "database information" not in str(exc.value)


def test_foreign_uploaded_receipt_cannot_be_attached_even_via_top_level_url(system, private_storage):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    foreign = f"{settings.supabase_url}/storage/v1/object/receipts/{orgs[0].id}/{users['adviser'].id}/{uuid4()}.jpg"
    response = client.post("/expenses", json={"event_id": str(resources[0]["events"].id),
        "category_id": str(resources[0]["categories"].id), "description": "Event supplies",
        "amount": "10.00", "receipt_url": foreign})
    assert response.status_code == 403, response.text
    db.rollback()
    response = client.post("/receipts", json={"expense_id": str(resources[0]["expenses"].id),
        "receipt_url": foreign, "purpose": "Event supplies", "issued_on": str(date.today())})
    assert response.status_code == 403, response.text
    db.rollback()
    own = foreign.replace(str(users["adviser"].id), str(users["treasurer"].id))
    response = client.post("/receipts", json={"expense_id": str(resources[0]["expenses"].id),
        "receipt_url": own + "?token=old", "purpose": "Event supplies"})
    assert response.status_code == 201, response.text
    assert response.json()["receipt_url"] == own
    assert resources[0]["expenses"].receipt_url == own


def test_receipt_scan_link_cannot_follow_uploader_to_another_organization(system, private_storage):
    client, db, users, orgs, resources, login = system
    user = users["treasurer"]
    old_scan = f"{settings.supabase_url}/storage/v1/object/receipts/{orgs[0].id}/{user.id}/{uuid4()}.jpg"
    user.organization_id = orgs[1].id
    db.commit()
    login("treasurer")
    response = client.post("/incomes", json={"event_id": str(resources[1]["events"].id),
        "source": "Donor", "purpose": "Event supplies", "amount": 10,
        "receipt": {"receipt_url": old_scan, "purpose": "Event supplies"}})
    assert response.status_code == 403, response.text


def test_legacy_public_url_fingerprints_still_prevent_duplicate_receipts(system, private_storage):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    url = f"{settings.supabase_url}/storage/v1/object/receipts/{orgs[0].id}/{users['treasurer'].id}/{uuid4()}.jpg"
    response = client.post("/incomes", json={"event_id": str(resources[0]["events"].id),
        "source": "Donor", "purpose": "Event supplies", "amount": 10,
        "receipt": {"receipt_url": url, "purpose": "Event supplies"}})
    assert response.status_code == 201, response.text
    receipt = db.query(Receipt).one()
    old_public_url = url.replace("/object/receipts/", "/object/public/receipts/")
    receipt.receipt_url = old_public_url
    receipt.url_fingerprint = fingerprint(old_public_url)
    db.commit()
    duplicate = client.post("/receipts", json={"expense_id": str(resources[0]["expenses"].id),
        "receipt_url": url, "purpose": "Event supplies"})
    assert duplicate.status_code == 409, duplicate.text
    assert duplicate.json()["detail"]["code"] == "duplicate_receipt"


def test_proposal_upload_rejects_empty_spoofed_and_oversized_files(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    uploads = []
    monkeypatch.setattr("app.routers.proposal_letters.upload_proposal_letter", lambda *args: uploads.append(args))
    for data, mime in ((b"", "application/pdf"), (b"fake pdf", "application/pdf"),
                       (b"not an image", "image/jpeg"), (b"x" * (storage.MAX_UPLOAD_BYTES + 1), "application/pdf")):
        response = client.post("/proposal-letters", data={"event_id": str(resources[0]["events"].id), "title": "Proposal"},
                               files={"file": ("proposal.pdf", data, mime)})
        assert response.status_code == 400, response.text
    assert uploads == []


@pytest.mark.parametrize("amount", [float("nan"), float("inf"), -1, True, "NaN", "1e100", 10**400])
def test_ocr_rejects_nonfinite_negative_boolean_and_oversized_amounts(amount):
    assert ocr._safe_parse_float(amount) is None


def test_ocr_shared_extraction_bounds_data_and_closes_client(monkeypatch):
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    closed = []

    class Client:
        def __init__(self, **kwargs):
            assert kwargs["http_options"].timeout == 30_000
            self.models = self

        def __enter__(self):
            return self

        def __exit__(self, *args):
            closed.append(True)

        def generate_content(self, **kwargs):
            assert kwargs["config"].max_output_tokens == 4096
            return type("Response", (), {"text": '{"merchant":"Store","date":"2026/9/20","amount":"1,234.50"}'})()

    monkeypatch.setattr(ocr.genai, "Client", Client)
    assert ocr.parse_receipt_text("Receipt text") == {"merchant": "Store", "date": date(2026, 9, 20), "amount": 1234.5}
    assert closed == [True]
    for text in (" ", "x" * 50_001):
        with pytest.raises(ocr.ReceiptParseError):
            ocr.parse_receipt_text(text)
