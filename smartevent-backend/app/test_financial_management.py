"""Financial recommendations tested using isolated records, not live services."""
from datetime import date, timedelta
import pytest
from app.test_access_management import system
from app.models import AuditLog, Expense, IncomeRecord, Receipt


def expense(system, *, event_index=0, amount="10.00", url=None, merchant=None, number=None):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    payload = {"event_id": str(resources[event_index]["events"].id),
               "category_id": str(resources[event_index]["categories"].id),
               "description": "Venue equipment", "amount": amount}
    if url:
        payload["receipt"] = {"receipt_url": url, "purpose": "Venue equipment", "merchant": merchant,
                              "receipt_number": number, "issued_on": "2026-09-20"}
    return client.post("/expenses", json=payload)


def attach(system, transaction, **kwargs):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    payload = {"expense_id": str(transaction.id), "receipt_url": "https://example.com/r1.jpg",
               "purpose": "Event supplies", "merchant": "School Store", "receipt_number": "ABC-1",
               "issued_on": "2026-09-20", **kwargs}
    return client.post("/receipts", json=payload)


def test_event_reports_show_actual_sources_expenses_and_receipts(system):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    event_id = str(resources[0]["events"].id)
    income = client.post("/incomes", json={"event_id": event_id, "source": "ACME Sponsor",
        "source_type": "sponsorship", "purpose": "Venue support", "amount": "250.10",
        "received_on": "2026-09-20", "receipt": {"receipt_url": "https://example.com/sponsor.jpg", "purpose": "Venue support"}})
    assert income.status_code == 201, income.text
    assert income.json()["source_type"] == "sponsorship"
    resources[0]["expenses"].status = "approved"
    db.commit()
    report = client.get(f"/reports/event/{event_id}").json()
    assert report["total_income"] == 350.1 and report["total_spent"] == 10
    assert report["net_balance"] == 340.1
    assert report["income_by_source"][1]["source"] == "ACME Sponsor"
    assert report["receipts"][0]["income_id"] == income.json()["id"]
    assert report["receipts"][0]["event_id"] == event_id


@pytest.mark.parametrize("period,params", [
    ("weekly", "&reference_date=2026-09-23"), ("monthly", "&reference_date=2026-09-23"),
    ("school_year", "&school_year=2026-2027"), ("semester", "&school_year=2026-2027&semester=1st")])
def test_financial_periods_filters_and_decimal_totals(system, period, params):
    client, db, users, orgs, resources, login = system
    # Remove fixture income, replace it with known accounting dates and values.
    db.delete(resources[0]["incomes"])
    db.add_all([IncomeRecord(event_id=resources[0]["events"].id, source="Donor", source_type="donation",
        purpose="Event", amount=amount, received_on=date(2026, 9, 23), recorded_by=users["treasurer"].id)
        for amount in ("0.10", "0.20")])
    resources[0]["expenses"].status = "approved"
    resources[0]["expenses"].amount = "0.10"
    resources[0]["expenses"].expense_date = date(2026, 9, 23)
    db.commit()
    login("officer")
    response = client.get(f"/reports/financial?period={period}{params}&event_scope=organizational")
    assert response.status_code == 200, response.text
    report = response.json()
    assert report["total_income"] == .3 and report["total_expenses"] == .1 and report["net_balance"] == .2
    assert report["income_by_source"] == [{"source_type": "donation", "source": "Donor", "income_count": 2, "total_income": .3}]
    assert len(report["events"]) == 1
    assert client.get(f"/reports/financial?period={period}{params}&event_scope=departmental").json()["total_income"] == 0


def test_calendar_reports_use_transaction_dates_not_event_creation_date(system):
    client, db, users, orgs, resources, login = system
    resources[0]["incomes"].received_on = date(2026, 8, 31)
    resources[0]["expenses"].status = "approved"
    resources[0]["expenses"].expense_date = date(2026, 9, 1)
    db.commit()
    login("officer")
    report = client.get("/reports/financial?period=monthly&reference_date=2026-09-20").json()
    assert report["total_income"] == 0 and report["total_expenses"] == 10


@pytest.mark.parametrize("field,value", [("source", "   "), ("purpose", " \n "), ("amount", "1.234"), ("amount", "NaN"), ("source_type", "unknown")])
def test_income_rejects_blank_sources_purposes_and_invalid_money(system, field, value):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    payload = {"event_id": str(resources[0]["events"].id), "source": "Donation", "purpose": "Event", "amount": "10.00", field: value}
    assert client.post("/incomes", json=payload).status_code == 422


def test_receipt_requires_event_purpose_and_exactly_one_transaction(system):
    client, db, users, orgs, resources, login = system
    transaction = resources[0]["expenses"]
    assert attach(system, transaction, purpose="   ").status_code == 422
    assert attach(system, transaction, income_id=str(resources[0]["incomes"].id)).status_code == 422
    assert attach(system, transaction, amount="12.00").status_code == 422
    transaction.event_id = None
    db.commit()
    assert attach(system, transaction).status_code == 422


@pytest.mark.parametrize("kind", ["url", "reference"])
def test_exact_receipt_duplicates_are_blocked_across_events(system, kind):
    client, db, users, orgs, resources, login = system
    assert attach(system, resources[0]["expenses"]).status_code == 201
    response = expense(system)
    assert response.status_code == 201
    # Resolve by UUID rather than relying on equal fixture timestamps.
    from uuid import UUID
    second = db.get(Expense, UUID(response.json()["id"]))
    payload = {"receipt_url": "https://example.com/r1.jpg?token=different" if kind == "url" else "https://example.com/r2.jpg",
               "receipt_number": "different" if kind == "url" else "  abc-1  ", "merchant": " SCHOOL STORE "}
    duplicate = attach(system, second, **payload)
    assert duplicate.status_code == 409, duplicate.text
    assert db.query(Receipt).count() == 1


def test_receipt_duplicates_block_atomic_income_creation(system):
    client, db, users, orgs, resources, login = system
    assert attach(system, resources[0]["expenses"]).status_code == 201
    login("treasurer")
    response = client.post("/incomes", json={"event_id": str(resources[0]["events"].id),
        "source": "Donation", "purpose": "Event", "amount": 10,
        "receipt": {"receipt_url": "https://example.com/r1.jpg", "purpose": "Event"}})
    assert response.status_code == 409
    db.rollback()  # Production get_db closes/rolls back failed requests.
    assert db.query(IncomeRecord).count() == 2


def test_similar_receipt_requires_independent_review_before_approval(system):
    client, db, users, orgs, resources, login = system
    first = attach(system, resources[0]["expenses"])
    response = expense(system, url="https://example.com/other.jpg", merchant=" school store ", number="ABC-2")
    assert response.status_code == 201, response.text
    from uuid import UUID
    second = db.get(Expense, UUID(response.json()["id"]))
    note = db.query(Receipt).filter(Receipt.expense_id == second.id).one()
    assert note.is_flagged and note.review_status == "pending"
    assert note.similar_receipt_ids == [first.json()["id"]]
    login("admin")
    assert client.post(f"/expenses/{second.id}/approve", json={}).status_code == 409
    assert client.post(f"/receipts/{note.id}/review", json={"reason": "Different original receipt verified"}).status_code == 200
    assert client.post(f"/expenses/{second.id}/approve", json={}).status_code == 200
    assert db.query(AuditLog).filter(AuditLog.action == "receipt.similarity_reviewed").count() == 1


@pytest.mark.parametrize("decision", ["cleared", "rejected"])
def test_similar_income_is_withheld_from_reports_until_cleared(system, decision):
    client, db, users, orgs, resources, login = system
    assert attach(system, resources[0]["expenses"]).status_code == 201
    login("treasurer")
    response = client.post("/incomes", json={"event_id": str(resources[0]["events"].id), "source": "Donor", "source_type": "donation",
        "purpose": "Supplies", "amount": 10, "received_on": "2026-09-20",
        "receipt": {"receipt_url": "https://example.com/donor.jpg", "purpose": "Supplies", "merchant": "School Store", "issued_on": "2026-09-21"}})
    assert response.status_code == 201, response.text
    assert response.json()["receipt_review_status"] == "pending"
    event_id = resources[0]["events"].id
    report = client.get(f"/reports/event/{event_id}").json()
    assert report["total_income"] == 100 and report["withheld_income_total"] == 10
    note = db.query(Receipt).filter(Receipt.income_id.is_not(None)).one()
    login("admin")
    assert client.post(f"/receipts/{note.id}/review", json={"decision": decision, "reason": "Original financial evidence checked"}).status_code == 200
    report = client.get("/reports/financial?period=school_year&school_year=2026-2027").json()
    assert report["total_income"] == (110 if decision == "cleared" else 100)
    assert report["withheld_income_total"] == (0 if decision == "cleared" else 10)


def test_receipt_review_cannot_be_bypassed_by_rewriting_metadata(system):
    client, db, users, orgs, resources, login = system
    assert attach(system, resources[0]["expenses"]).status_code == 201
    response = expense(system, url="https://example.com/other.jpg", merchant="School Store", number="ABC-2")
    from uuid import UUID
    second = db.get(Expense, UUID(response.json()["id"]))
    rewritten = attach(system, second, receipt_url="https://example.com/rewrite.jpg", merchant=None, receipt_number=None)
    assert rewritten.status_code == 201 and rewritten.json()["review_status"] == "pending"
    note_id = rewritten.json()["id"]
    login("admin")
    assert client.post(f"/receipts/{note_id}/review", json={"reason": "Original evidence shows distinct receipts"}).status_code == 200
    assert attach(system, second, receipt_url="https://example.com/change.jpg").status_code == 409


def test_receipt_scope_and_role_restrictions(system):
    client, db, users, orgs, resources, login = system
    response = attach(system, resources[0]["expenses"])
    note_id = response.json()["id"]
    login("officer")
    assert client.get(f"/receipts/{note_id}").status_code == 200
    assert client.post(f"/receipts/{note_id}/review", json={"reason": "Checking receipt evidence"}).status_code == 403
    login("super_admin")
    foreign = client.post("/receipts", json={"expense_id": str(resources[1]["expenses"].id),
        "receipt_url": "https://example.com/r1.jpg", "purpose": "Foreign event supplies"})
    assert foreign.status_code == 201  # duplicate scope is organization, not global
    login("officer")
    assert client.get(f"/receipts/{foreign.json()['id']}").status_code == 403
    assert len(client.get("/receipts").json()) == 1
    login("sds_staff")
    assert client.get("/receipts").status_code == 403


def test_uploaded_receipt_hash_is_server_computed_and_reuse_is_blocked(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    first = attach(system, resources[0]["expenses"])
    response = expense(system)
    from uuid import UUID
    second = attach(system, db.get(Expense, UUID(response.json()["id"])), receipt_url="https://example.com/r2.jpg", merchant=None, receipt_number=None)
    monkeypatch.setattr("app.routers.receipts.prepare_image_for_upload", lambda raw: (raw, "image/jpeg"))
    monkeypatch.setattr("app.routers.receipts.upload_receipt_image", lambda *a: "https://example.com/uploaded.jpg")
    uploaded = client.post(f"/receipts/{first.json()['id']}/upload", files={"file": ("receipt.jpg", b"sample bytes", "image/jpeg")})
    assert uploaded.status_code == 200, uploaded.text
    duplicate = client.post(f"/receipts/{second.json()['id']}/upload", files={"file": ("copy.jpg", b"sample bytes", "image/jpeg")})
    assert duplicate.status_code == 409


def test_exports_include_sources_and_receipt_review_information(system):
    client, db, users, orgs, resources, login = system
    login("officer")
    event_id = resources[0]["events"].id
    for format in ("csv", "html", "pdf"):
        response = client.get(f"/reports/event/{event_id}/export?format={format}")
        assert response.status_code == 200
        if format != "pdf":
            assert "Income by source" in response.text and "Receipt review" in response.text


def test_legacy_receipt_urls_are_not_reusable_and_receipted_fields_cannot_change(system):
    client, db, users, orgs, resources, login = system
    original = resources[0]["expenses"]
    original.receipt_url = "https://example.com/legacy.jpg"
    db.commit()
    response = expense(system)
    from uuid import UUID
    second = db.get(Expense, UUID(response.json()["id"]))
    assert attach(system, second, receipt_url="https://example.com/legacy.jpg?token=abc").status_code == 409
    receipt = attach(system, original, receipt_url="https://example.com/legacy.jpg")
    assert receipt.status_code == 201
    for patch in ({"event_id": None}, {"amount": 20}, {"expense_date": "2026-10-01"}, {"receipt_url": None}):
        assert client.patch(f"/expenses/{original.id}", json=patch).status_code in (409, 422)
    assert client.delete(f"/expenses/{original.id}").status_code == 409


def test_no_self_review_or_blank_review_reason(system):
    client, db, users, orgs, resources, login = system
    assert attach(system, resources[0]["expenses"]).status_code == 201
    response = expense(system, url="https://example.com/flagged.jpg", merchant="School Store", number="ABC-2")
    from uuid import UUID
    transaction = db.get(Expense, UUID(response.json()["id"]))
    note = db.query(Receipt).filter(Receipt.expense_id == transaction.id).one()
    note.recorded_by = users["admin"].id
    db.commit()
    login("admin")
    assert client.post(f"/receipts/{note.id}/review", json={"reason": "Checked original records carefully"}).status_code == 403
    login("adviser")
    assert client.post(f"/receipts/{note.id}/review", json={"reason": "           "}).status_code == 422
    assert client.post(f"/receipts/{note.id}/review", json={"decision": "rejected", "reason": "Receipt appears to be the same purchase"}).status_code == 200
    login("admin")
    assert client.post(f"/expenses/{transaction.id}/approve", json={}).status_code == 409
