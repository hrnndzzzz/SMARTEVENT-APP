"""Event-scoped inventory and documented purchase completion in isolated SQLite."""
from datetime import date, timedelta
from uuid import UUID, uuid4
import pytest
from app.test_access_management import system
from app.models import AuditLog, Expense, ExpenseItem, Inventory, InventoryTransaction


def create_asset_expense(system, name="Chair", unit="pcs", receipt=True):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    payload = {"event_id": str(resources[0]["events"].id), "category_id": str(resources[0]["categories"].id),
               "description": "Purchase of equipment", "amount": 60,
               "items": [{"name": name, "amount": 60, "category": "asset", "quantity": 3, "unit": unit}]}
    if receipt:
        payload["receipt"] = {"receipt_url": "https://example.com/" + str(uuid4()) + ".jpg", "purpose": "Equipment purchase"}
    response = client.post("/expenses", json=payload)
    assert response.status_code == 201, response.text
    expense = db.get(Expense, UUID(response.json()["id"]))
    line = db.query(ExpenseItem).filter(ExpenseItem.expense_id == expense.id).one()
    return expense, line


def completion_payload(line, **overrides):
    return {"paid_on": date.today().isoformat(), "received_on": date.today().isoformat(),
            "paid_amount": "60.00", "payment_method": "cash", "payment_reference": "OR-PAY-1",
            "vendor": "Equipment Supplier", "items": [{"expense_item_id": str(line.id), "quantity": 3, "unit": line.unit}], **overrides}


def approve(system, expense):
    client, db, users, orgs, resources, login = system
    login("admin")
    response = client.post(f"/expenses/{expense.id}/approve", json={})
    assert response.status_code == 200, response.text


def move(system, transaction_type, quantity, event_index=0):
    client, db, users, orgs, resources, login = system
    return client.post(f"/inventory/{resources[0]['inventory'].id}/transactions", json={
        "event_id": str(resources[event_index]["events"].id), "transaction_type": transaction_type,
        "change_qty": quantity, "reason": "Recorded movement"})


def test_approval_does_not_add_stock_and_complete_purchase_does_once(system):
    client, db, users, orgs, resources, login = system
    expense, line = create_asset_expense(system)
    assert line.quantity == 3
    approve(system, expense)
    assert resources[0]["inventory"].quantity == 10
    assert line.converted_inventory_id is None
    login("treasurer")
    response = client.post(f"/expenses/{expense.id}/complete-purchase", json=completion_payload(line))
    assert response.status_code == 200, response.text
    assert response.json()["purchase_completed_at"] is not None
    assert response.json()["paid_amount"] == 60
    assert resources[0]["inventory"].quantity == 13
    assert line.converted_inventory_id == resources[0]["inventory"].id
    movement = db.query(InventoryTransaction).filter(InventoryTransaction.expense_item_id == line.id).one()
    assert movement.transaction_type == "purchase" and movement.change_qty == 3
    assert movement.event_id == expense.event_id
    assert client.post(f"/expenses/{expense.id}/complete-purchase", json=completion_payload(line)).status_code == 409
    assert resources[0]["inventory"].quantity == 13
    assert db.query(AuditLog).filter(AuditLog.action == "purchase.completed").count() == 1


def test_new_purchased_item_is_received_as_catalog_draft_with_event_and_history(system):
    client, db, users, orgs, resources, login = system
    expense, line = create_asset_expense(system, name="Projector")
    approve(system, expense)
    assert db.query(Inventory).filter(Inventory.item_name == "Projector").first() is None
    login("treasurer")
    assert client.post(f"/expenses/{expense.id}/complete-purchase", json=completion_payload(line)).status_code == 200
    item = db.query(Inventory).filter(Inventory.item_name == "Projector").one()
    assert item.quantity == 3 and item.is_draft and item.event_id == expense.event_id
    payload = {"event_id": str(expense.event_id), "transaction_type": "issue", "change_qty": -1, "reason": "Seminar use"}
    assert client.post(f"/inventory/{item.id}/transactions", json=payload).status_code == 409
    login("admin")
    assert client.post(f"/inventory/{item.id}/confirm-draft").status_code == 200
    assert client.post(f"/inventory/{item.id}/transactions", json=payload).status_code == 201
    assert item.quantity == 2


@pytest.mark.parametrize("problem,expected", [("pending", 409), ("no_receipt", 409), ("underpaid", 422),
    ("future", 422), ("foreign_line", 422), ("duplicate_line", 422), ("unit", 422), ("legacy_converted", 409)])
def test_incomplete_purchase_never_adds_stock(system, problem, expected):
    client, db, users, orgs, resources, login = system
    expense, line = create_asset_expense(system)
    if problem != "pending":
        approve(system, expense)
    payload = completion_payload(line)
    if problem == "no_receipt":
        from app.models import Receipt
        db.delete(db.query(Receipt).filter(Receipt.expense_id == expense.id).one())
    elif problem == "underpaid":
        payload["paid_amount"] = 30
    elif problem == "future":
        payload["received_on"] = (date.today() + timedelta(days=1)).isoformat()
    elif problem == "foreign_line":
        payload["items"][0]["expense_item_id"] = str(uuid4())
    elif problem == "duplicate_line":
        payload["items"].append(payload["items"][0].copy())
    elif problem == "unit":
        payload["items"][0]["unit"] = "boxes"
    elif problem == "legacy_converted":
        line.converted_inventory_id = resources[0]["inventory"].id
    db.commit()
    login("treasurer")
    response = client.post(f"/expenses/{expense.id}/complete-purchase", json=payload)
    assert response.status_code == expected, response.text
    assert resources[0]["inventory"].quantity == 10
    assert db.query(InventoryTransaction).count() == 0
    assert expense.purchase_completed_at is None


def test_asset_expense_requires_receipt_before_approval(system):
    client, db, users, orgs, resources, login = system
    expense, line = create_asset_expense(system, receipt=False)
    login("admin")
    assert client.post(f"/expenses/{expense.id}/approve", json={}).status_code == 409
    assert expense.status == "pending"


def test_new_inventory_has_event_link_and_opening_stock_ledger(system):
    client, db, users, orgs, resources, login = system
    login("admin")
    assert client.post("/inventory", json={"item_name": "Table"}).status_code == 422
    response = client.post("/inventory", json={"item_name": "Table", "event_id": str(resources[0]["events"].id),
        "quantity": 4, "initial_transaction_type": "donation", "reason": "Alumni donation"})
    assert response.status_code == 201, response.text
    history = client.get(f"/inventory/{response.json()['id']}/transactions").json()
    assert history[0]["transaction_type"] == "donation" and history[0]["change_qty"] == 4
    assert history[0]["event_id"] == str(resources[0]["events"].id)
    assert client.post("/inventory", json={"item_name": "Purchased", "event_id": str(resources[0]["events"].id),
        "initial_transaction_type": "purchase", "quantity": 10}).status_code == 422


@pytest.mark.parametrize("kind,qty,expected", [("donation", 2, 201), ("acquisition", 2, 201), ("issue", -2, 201),
    ("disposal", -1, 201), ("adjustment", 1, 201), ("purchase", 1, 409), ("return", 1, 409),
    ("issue", 2, 422), ("donation", -1, 422), ("disposal", -11, 409), ("adjustment", 0, 422)])
def test_transaction_type_signs_and_stock_guards(system, kind, qty, expected):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    response = move(system, kind, qty)
    assert response.status_code == expected, response.text
    assert resources[0]["inventory"].quantity == (10 + qty if expected == 201 else 10)


def test_returns_cannot_exceed_event_issue_quantity(system):
    client, db, users, orgs, resources, login = system
    login("adviser")
    assert move(system, "issue", -3).status_code == 201
    assert move(system, "return", 2).status_code == 201
    assert move(system, "return", 2).status_code == 409
    assert move(system, "return", 1).status_code == 201
    assert resources[0]["inventory"].quantity == 10


def test_movements_require_event_type_and_reason_and_stay_scoped(system):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    path = f"/inventory/{resources[0]['inventory'].id}/transactions"
    base = {"event_id": str(resources[0]["events"].id), "transaction_type": "donation", "change_qty": 1, "reason": "Gift"}
    for field in ("event_id", "transaction_type", "reason"):
        assert client.post(path, json={key: value for key, value in base.items() if key != field}).status_code == 422
    assert move(system, "donation", 1, event_index=1).status_code == 403
    login("officer")
    assert move(system, "donation", 1).status_code == 403
    login("sds_staff")
    assert client.get("/inventory").status_code == 403


def test_legacy_item_and_movement_repair_is_audited_without_replaying_quantity(system):
    client, db, users, orgs, resources, login = system
    item = resources[0]["inventory"]
    item.event_id = None
    history = InventoryTransaction(inventory_id=item.id, change_qty=2, performed_by=users["treasurer"].id)
    db.add(history)
    db.commit()
    login("treasurer")
    assert move(system, "donation", 1).status_code == 409
    login("admin")
    assert len(client.get("/inventory?missing_event=true").json()) == 1
    assert client.patch(f"/inventory/{item.id}", json={"event_id": str(resources[0]["events"].id)}).status_code == 200
    path = f"/inventory/{item.id}/transactions/{history.id}/metadata"
    payload = {"event_id": str(resources[0]["events"].id), "transaction_type": "donation", "reason": "Verified historical donation"}
    assert client.patch(path, json=payload).status_code == 200
    assert item.quantity == 10 and history.change_qty == 2
    assert client.patch(path, json=payload).status_code == 409
    assert db.query(AuditLog).filter(AuditLog.action == "inventory.legacy_movement_repaired").count() == 1


def test_inventory_filters_and_metadata_cannot_bypass_stock_ledger(system):
    client, db, users, orgs, resources, login = system
    login("admin")
    item = resources[0]["inventory"]
    assert client.patch(f"/inventory/{item.id}", json={"quantity": 100}).status_code == 422
    assert client.patch(f"/inventory/{item.id}", json={"event_id": None}).status_code == 422
    assert client.delete(f"/inventory/{item.id}").status_code == 409
    login("officer")
    assert len(client.get(f"/inventory?event_id={resources[0]['events'].id}").json()) == 1
    assert client.get(f"/inventory?event_id={resources[1]['events'].id}").json() == []


@pytest.mark.parametrize("role", ["officer", "adviser", "sds_staff"])
def test_purchase_completion_requires_financial_execution_role(system, role):
    client, db, users, orgs, resources, login = system
    expense, line = create_asset_expense(system)
    approve(system, expense)
    login(role)
    assert client.post(f"/expenses/{expense.id}/complete-purchase", json=completion_payload(line)).status_code == 403
