import asyncio
import hashlib
from decimal import Decimal
from types import SimpleNamespace
from uuid import UUID

import pytest
from fastapi import HTTPException

from app.models import Expense, ExpenseItem, InventoryTransaction, Receipt
from app.routers.expenses import _read_receipt_image
from app.services.report_exports import render_export
from app.test_access_management import system
from app.test_inventory_management import approve, completion_payload, create_asset_expense, move


@pytest.mark.parametrize("module", ["events", "categories"])
def test_allocation_changes_preserve_spending_and_reject_overdrawn_budget(system, module):
    client, db, users, orgs, resources, login = system
    record = resources[0][module]
    if module == "events":
        record.status = "draft"
    record.remaining_budget = Decimal("800.00")
    db.commit()
    login("admin")
    path = f"/{module}/{record.id}"
    response = client.patch(path, json={"allocated_budget": "600.00"})
    assert response.status_code == 200, response.text
    assert response.json()["remaining_budget"] == 400
    response = client.patch(path, json={"allocated_budget": "199.99"})
    assert response.status_code == 409, response.text
    assert record.allocated_budget == 600 and record.remaining_budget == 400


@pytest.mark.parametrize("module", ["events", "categories"])
def test_reduced_allocation_limits_expense_approval(system, module):
    client, db, users, orgs, resources, login = system
    record = resources[0][module]
    if module == "events":
        record.status = "draft"
        db.commit()
    login("admin")
    assert client.patch(f"/{module}/{record.id}", json={"allocated_budget": 5}).status_code == 200
    response = client.post(f"/expenses/{resources[0]['expenses'].id}/approve", json={})
    assert response.status_code == 409, response.text
    assert resources[0]["expenses"].status == "pending"


@pytest.mark.parametrize("action", ["approve", "reject"])
def test_foreign_expense_state_is_not_disclosed_to_reviewer(system, action):
    client, db, users, orgs, resources, login = system
    expense = resources[1]["expenses"]
    expense.status = "approved"
    db.commit()
    login("adviser")
    response = client.post(f"/expenses/{expense.id}/{action}", json={})
    assert response.status_code == 403, response.text
    assert "approved" not in response.text


def test_receipt_reader_bounds_memory_before_image_processing(monkeypatch):
    reads = []
    async def read(size):
        reads.append(size)
        return b"x" * size
    monkeypatch.setattr("app.routers.expenses.prepare_image_for_upload", lambda raw: pytest.fail("must reject oversized images first"))
    with pytest.raises(HTTPException) as exc:
        asyncio.run(_read_receipt_image(SimpleNamespace(content_type="image/jpeg", read=read)))
    assert exc.value.status_code == 400
    assert reads == [10 * 1024 * 1024 + 1]


def test_scan_receipt_uses_authorized_organization_storage_path(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    uploaded = []
    monkeypatch.setattr("app.routers.expenses.prepare_image_for_upload", lambda raw: (raw, "image/jpeg"))
    monkeypatch.setattr("app.routers.expenses.parse_receipt_image", lambda *args: {
        "merchant": "Store", "date": None, "amount": 10, "items": [],
    })
    def upload(raw, content_type, owner_id, organization_id):
        uploaded.append((owner_id, organization_id))
        return "https://example.com/upload.jpg"
    monkeypatch.setattr("app.routers.expenses.upload_receipt_image", upload)
    file = {"file": ("receipt.jpg", b"image", "image/jpeg")}
    login("treasurer")
    assert client.post("/expenses/scan-receipt", files=file).status_code == 200
    assert uploaded == [(users["treasurer"].id, orgs[0].id)]
    assert client.post("/expenses/scan-receipt", files=file,
        data={"organization_id": str(orgs[1].id)}).status_code == 403
    assert len(uploaded) == 1
    login("super_admin")
    assert client.post("/expenses/scan-receipt", files=file).status_code == 403
    assert client.post("/expenses/scan-receipt", files=file,
        data={"organization_id": str(orgs[1].id)}).status_code == 403
    assert uploaded == [(users["treasurer"].id, orgs[0].id)]


@pytest.mark.parametrize("route,error,status", [
    ("scan-receipt", RuntimeError, 503), ("scan-receipt", ValueError, 502),
    ("parse-receipt", RuntimeError, 503), ("parse-receipt", ValueError, 502),
])
def test_receipt_provider_failures_do_not_expose_secrets(system, monkeypatch, route, error, status):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    monkeypatch.setattr("app.routers.expenses.prepare_image_for_upload", lambda raw: (raw, "image/jpeg"))
    monkeypatch.setattr("app.routers.expenses.upload_receipt_image", lambda *args: "https://example.com/upload.jpg")
    def fail(*args):
        raise error("private-provider-key-and-response")
    if route == "scan-receipt":
        monkeypatch.setattr("app.routers.expenses.parse_receipt_image", fail)
        response = client.post("/expenses/scan-receipt", files={"file": ("receipt.jpg", b"image", "image/jpeg")})
    else:
        monkeypatch.setattr("app.routers.expenses.parse_receipt_text", fail)
        response = client.post(f"/expenses/{resources[0]['expenses'].id}/parse-receipt", json={"raw_text": "Receipt total PHP 10.00"})
    assert response.status_code == status, response.text
    assert "private-provider" not in response.text


def test_reviewed_evidence_blocks_expense_upload_before_storage(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    expense = resources[0]["expenses"]
    response = client.post("/receipts", json={"expense_id": str(expense.id),
        "receipt_url": "https://example.com/receipt.jpg", "purpose": "Equipment"})
    assert response.status_code == 201, response.text
    db.query(Receipt).filter(Receipt.expense_id == expense.id).one().review_status = "cleared"
    db.commit()
    monkeypatch.setattr("app.routers.expenses.upload_receipt_image", lambda *args: pytest.fail("reviewed evidence cannot be uploaded"))
    response = client.post(f"/expenses/{expense.id}/receipt", files={"file": ("receipt.jpg", b"image", "image/jpeg")})
    assert response.status_code == 409, response.text


def test_expense_upload_rejects_existing_income_file_before_storage(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    income = resources[0]["incomes"]
    response = client.post("/receipts", json={"income_id": str(income.id),
        "receipt_url": "https://example.com/donation.jpg", "purpose": "Donation"})
    assert response.status_code == 201, response.text
    db.query(Receipt).filter(Receipt.income_id == income.id).one().file_sha256 = hashlib.sha256(b"image").hexdigest()
    db.commit()
    monkeypatch.setattr("app.routers.expenses.prepare_image_for_upload", lambda raw: (raw, "image/jpeg"))
    monkeypatch.setattr("app.routers.expenses.upload_receipt_image", lambda *args: pytest.fail("duplicate file cannot be uploaded"))
    response = client.post(f"/expenses/{resources[0]['expenses'].id}/receipt",
        files={"file": ("receipt.jpg", b"image", "image/jpeg")})
    assert response.status_code == 409, response.text


@pytest.mark.parametrize("purchase", [False, True])
def test_stock_overflow_does_not_change_inventory_or_ledger(system, purchase):
    client, db, users, orgs, resources, login = system
    item = resources[0]["inventory"]
    item.quantity = 2**31 - 1
    db.commit()
    if purchase:
        expense, line = create_asset_expense(system)
        approve(system, expense)
        login("treasurer")
        response = client.post(f"/expenses/{expense.id}/complete-purchase", json=completion_payload(line))
        assert expense.purchase_completed_at is None and line.converted_inventory_id is None
    else:
        login("treasurer")
        response = move(system, "donation", 1)
    assert response.status_code == 409, response.text
    assert item.quantity == 2**31 - 1
    assert db.query(InventoryTransaction).count() == 0


@pytest.mark.parametrize("quantity,status", [(10, 200), (2**31 - 5, 409)])
def test_repeated_catalog_purchase_lines_apply_once_and_guard_combined_stock(system, quantity, status):
    client, db, users, orgs, resources, login = system
    item = resources[0]["inventory"]
    item.quantity = quantity
    db.commit()
    login("treasurer")
    response = client.post("/expenses", json={
        "event_id": str(resources[0]["events"].id), "category_id": str(resources[0]["categories"].id),
        "description": "Chair purchase", "amount": 60,
        "items": [{"name": name, "amount": 30, "category": "asset", "quantity": 1, "unit": "pcs"}
                  for name in ("Chair", "CHAIR")],
        "receipt": {"receipt_url": "https://example.com/chairs.jpg", "purpose": "Chair purchase"},
    })
    assert response.status_code == 201, response.text
    expense = db.get(Expense, UUID(response.json()["id"]))
    lines = db.query(ExpenseItem).filter(ExpenseItem.expense_id == expense.id).order_by(ExpenseItem.name).all()
    approve(system, expense)
    login("treasurer")
    payload = completion_payload(lines[0], items=[
        {"expense_item_id": str(line.id), "quantity": added, "unit": "pcs"}
        for line, added in zip(lines, (2, 3))
    ])
    response = client.post(f"/expenses/{expense.id}/complete-purchase", json=payload)
    assert response.status_code == status, response.text
    assert item.quantity == quantity + (5 if status == 200 else 0)
    assert db.query(InventoryTransaction).count() == (2 if status == 200 else 0)
    if status == 200:
        assert all(line.converted_inventory_id == item.id for line in lines)
    else:
        assert expense.purchase_completed_at is None
        assert all(line.converted_inventory_id is None for line in lines)


def test_report_downloads_and_filters_protect_financial_data(system):
    client, db, users, orgs, resources, login = system
    login("officer")
    response = client.get("/reports/financial.pdf?period=school_year&school_year=2026-2027")
    assert response.status_code == 200, response.text
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-content-type-options"] == "nosniff"
    for months in (-1, 0, 121):
        assert client.get(f"/analytics/spending-trends?months={months}").status_code == 422


def test_csv_formula_guards_apply_to_titles_and_columns():
    body = render_export("=TITLE()", [("=SECTION()", ["=COLUMN()"], [["=CELL()"]])], "csv", "report").body.decode("utf-8-sig")
    for formula in ("=TITLE()", "=SECTION()", "=COLUMN()", "=CELL()"):
        assert "'" + formula in body
