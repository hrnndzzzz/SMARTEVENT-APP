from datetime import datetime, timedelta, timezone
from uuid import uuid4

from app.config import settings
from app.models import Receipt
from app.services.receipt_retention import purge_old_receipt_files
from app.test_access_management import system  # noqa: F401
from app.test_storage_security import private_storage  # noqa: F401


def test_receipt_photos_older_than_30_days_are_deleted_and_the_record_kept(system, private_storage):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    base = f"{settings.supabase_url}/storage/v1/object/receipts/{orgs[0].id}/{users['treasurer'].id}/"
    old_url, new_url = base + f"{uuid4()}.jpg", base + f"{uuid4()}.jpg"
    for url in (old_url, new_url):
        response = client.post("/incomes", json={"event_id": str(resources[0]["events"].id),
            "source": "Donor", "purpose": "Event supplies", "amount": 10,
            "receipt": {"receipt_url": url, "purpose": "Event supplies"}})
        assert response.status_code == 201, response.text
    old = db.query(Receipt).filter(Receipt.receipt_url == old_url).one()
    old.created_at = datetime.now(timezone.utc) - timedelta(days=31)
    db.commit()
    private_storage.clear()

    assert purge_old_receipt_files(db) == 1
    deletes = [r for r in private_storage if r[0] == "DELETE"]
    assert len(deletes) == 1 and deletes[0][1].endswith("/object/receipts")
    assert deletes[0][2]["json"]["prefixes"] == [old_url.split("/receipts/", 1)[1]]
    db.refresh(old)
    assert old.file_deleted_at is not None and old.amount == 10
    assert db.query(Receipt).filter(Receipt.receipt_url == new_url).one().file_deleted_at is None

    private_storage.clear()
    assert purge_old_receipt_files(db) == 0
    assert not private_storage

    gone = client.get("/files", params={"reference": old_url})
    assert gone.status_code == 410, gone.text
    assert "30 days" in gone.json()["detail"]
    assert client.get("/files", params={"reference": new_url}).status_code == 200


def test_a_storage_failure_leaves_receipts_for_the_next_run(system, private_storage, monkeypatch):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    url = f"{settings.supabase_url}/storage/v1/object/receipts/{orgs[0].id}/{users['treasurer'].id}/{uuid4()}.jpg"
    assert client.post("/incomes", json={"event_id": str(resources[0]["events"].id),
        "source": "Donor", "purpose": "Event supplies", "amount": 10,
        "receipt": {"receipt_url": url, "purpose": "Event supplies"}}).status_code == 201
    receipt = db.query(Receipt).one()
    receipt.created_at = datetime.now(timezone.utc) - timedelta(days=40)
    db.commit()

    from app.services import receipt_retention, storage

    def down(*args, **kwargs):
        raise storage.StorageError("down")

    monkeypatch.setattr(receipt_retention, "delete_uploaded_file", down)
    assert purge_old_receipt_files(db) == 0
    db.refresh(receipt)
    assert receipt.file_deleted_at is None


def test_the_server_starts_the_daily_cleanup_when_storage_is_configured(monkeypatch):
    from fastapi.testclient import TestClient
    from app.main import app

    started = []
    monkeypatch.setattr("app.services.receipt_retention.start_receipt_cleanup", lambda factory: started.append(factory))
    monkeypatch.setattr(settings, "app_env", "development")  # the live demo server runs as development
    monkeypatch.setattr(settings, "supabase_url", "https://storage.example.com")
    monkeypatch.setattr(settings, "supabase_service_key", "server-only-key")
    with TestClient(app):
        pass
    assert len(started) == 1
