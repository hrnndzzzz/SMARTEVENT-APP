"""Officers record money like the treasurer, and every member sees who last changed what."""
from datetime import date, datetime, timedelta, timezone

from app.models import AuditLog
from app.test_access_management import system  # noqa: F401 - shared fixture


def new_expense(resources, **extra):
    return {"category_id": str(resources[0]["categories"].id), "event_id": str(resources[0]["events"].id),
            "description": "Snacks", "amount": "25.00", **extra}


def test_officer_records_money_and_manages_only_own_pending_expenses(system):
    client, db, users, orgs, resources, login = system
    login("officer")
    income = client.post("/incomes", json={"event_id": str(resources[0]["events"].id), "source": "Sponsor",
                                           "purpose": "Snacks", "amount": "50.00"})
    assert income.status_code == 201, income.text
    created = client.post("/expenses", json=new_expense(resources))
    assert created.status_code == 201, created.text
    expense_id = created.json()["id"]
    assert client.patch(f"/expenses/{expense_id}", json={"description": "Snacks and water"}).status_code == 200
    # The seeded expense is the treasurer's, so it stays theirs to change.
    assert client.patch(f"/expenses/{resources[0]['expenses'].id}", json={"description": "Mine"}).status_code == 403
    assert client.delete(f"/expenses/{resources[0]['expenses'].id}").status_code == 403
    # Recording is not reviewing.
    assert client.post(f"/expenses/{expense_id}/approve", json={}).status_code == 403
    assert client.delete(f"/expenses/{expense_id}").status_code == 204


def test_manual_entries_and_look_alikes_are_flagged_when_saved(system):
    client, db, users, orgs, resources, login = system
    login("officer")
    manual = client.post("/expenses", json=new_expense(resources, manual_entry_reason="Vendor gave no receipt"))
    assert manual.status_code == 201, manual.text
    assert manual.json()["is_flagged"] is True
    assert "Vendor gave no receipt" in manual.json()["flag_reason"]
    # Same name, amount and day as the treasurer's still-pending seeded expense.
    look_alike = client.post("/expenses", json=new_expense(resources, description=" SUPPLIES ", amount="10.00"))
    assert look_alike.json()["is_flagged"] is True
    assert "Possible duplicate of Supplies" in look_alike.json()["flag_reason"]
    different = client.post("/expenses", json=new_expense(resources, description="Paper", amount="10.00"))
    assert different.json()["is_flagged"] is False


def test_scan_warns_about_a_recorded_look_alike_in_the_same_organization(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    monkeypatch.setattr("app.routers.expenses.prepare_image_for_upload", lambda raw: (raw, "image/jpeg"))
    monkeypatch.setattr("app.routers.expenses.upload_receipt_image", lambda *args: "https://example.com/scan.jpg")
    monkeypatch.setattr("app.routers.expenses.parse_receipt_image", lambda *args: {
        "merchant": "Supplies", "date": date.today(), "amount": 10.0, "items": [],
    })
    login("officer")
    response = client.post("/expenses/scan-receipt", files={"file": ("r.jpg", b"image", "image/jpeg")})
    assert response.status_code == 200, response.text
    # Organization B has the same seeded expense; it is not this officer's to see.
    assert [row["id"] for row in response.json()["possible_duplicates"]] == [str(resources[0]["expenses"].id)]


def test_saved_expense_keeps_the_receipt_reading(system):
    client, db, users, orgs, resources, login = system
    login("officer")
    created = client.post("/expenses", json=new_expense(resources, merchant="Corner Cafe", expense_date="2026-11-02",
        receipt={"receipt_url": "https://example.com/cafe.jpg", "purpose": "Meeting snacks",
                 "merchant": "Corner Cafe", "issued_on": "2026-11-01"}))
    assert created.status_code == 201, created.text
    body = created.json()
    assert (body["ocr_merchant"], body["ocr_date"], body["ocr_amount"]) == ("Corner Cafe", "2026-11-01", 25.0)


def test_latest_change_names_who_and_what_within_scope(system):
    client, db, users, orgs, resources, login = system
    login("officer")
    expense_id = client.post("/expenses", json=new_expense(resources)).json()["id"]
    # SQLite stamps to the second; date the first entry back so the order is certain.
    db.query(AuditLog).filter(AuditLog.action == "expense.recorded").update(
        {"created_at": datetime(2026, 1, 1, tzinfo=timezone.utc)})
    db.commit()
    assert client.delete(f"/expenses/{expense_id}").status_code == 204
    later = datetime.now(timezone.utc) + timedelta(days=1)
    db.add_all([
        AuditLog(user_id=users["officer"].id, action="user.password_changed", organization_id=orgs[0].id,
                 department_id=orgs[0].department_id, created_at=later),
        AuditLog(user_id=users["admin"].id, action="expense.recorded", organization_id=orgs[1].id,
                 department_id=orgs[1].department_id, entity_type="expenses",
                 entity_id=resources[1]["expenses"].id, created_at=later),
    ])
    db.commit()

    login("treasurer")
    latest = client.get("/audit-logs/latest", params={"area": "finance"})
    assert latest.status_code == 200, latest.text
    assert {key: latest.json()[key] for key in ("action", "actor_name", "subject")} == {
        "action": "expense.deleted", "actor_name": "officer", "subject": "Snacks"}
    record = client.get("/audit-logs/latest", params={"area": "finance", "entity_id": expense_id})
    assert record.json()["action"] == "expense.deleted"
    assert client.get("/audit-logs/latest", params={"area": "inventory"}).json() is None
    assert client.get("/audit-logs/latest", params={"area": "accounts"}).status_code == 422
