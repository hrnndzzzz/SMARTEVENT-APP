"""Exercise authorization with real records in an isolated SQLite database."""

from datetime import date
from uuid import uuid4

import pytest
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.models import (
    AuditLog, Category, CiteMember, Department, Event, Expense,
    IncomeRecord, Inventory, Organization, User,
)
from app.security import create_access_token


@compiles(JSONB, "sqlite")
def sqlite_jsonb(type_, compiler, **kwargs):
    return "JSON"


@pytest.fixture
def system():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    @event.listens_for(engine, "connect")
    def enable_foreign_keys(connection, record):
        connection.execute("PRAGMA foreign_keys=ON")
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    original = app.dependency_overrides.copy()
    app.dependency_overrides[get_db] = lambda: db
    department = Department(code="CITE", name="CITE")
    db.add(department)
    db.flush()
    organizations = [
        Organization(code="A", name="Organization A", department_id=department.id),
        Organization(code="B", name="Organization B", department_id=department.id),
    ]
    db.add_all(organizations)
    db.flush()
    accounts = {}
    for role in ("super_admin", "admin", "adviser", "treasurer", "officer", "sds_staff"):
        account = User(
            full_name=role, email=role + "@example.com", password_hash="unused",
            role=role, is_active=True, must_change_password=False,
            department_id=department.id if role not in ("super_admin", "sds_staff") else None,
            organization_id=organizations[0].id if role not in ("super_admin", "sds_staff") else None,
        )
        db.add(account)
        accounts[role] = account
    db.flush()
    resources = []
    for index, organization in enumerate(organizations):
        category = Category(name="Supplies", organization_id=organization.id, department_id=department.id,
                            created_by=accounts["admin"].id, allocated_budget=1000, remaining_budget=1000)
        db.add(category)
        db.flush()
        event_record = Event(
            organization_id=organization.id, department_id=department.id, category_id=category.id,
            title=f"Event {index}", proposed_by=accounts["treasurer"].id, status="pending",
            school_year="2026-2027", semester="1st", event_scope="organizational",
            allocated_budget=1000, remaining_budget=1000,
        )
        db.add(event_record)
        db.flush()
        expense = Expense(
            organization_id=organization.id, department_id=department.id, category_id=category.id,
            event_id=event_record.id, description="Supplies", amount=10, expense_date=date.today(),
            recorded_by=accounts["treasurer"].id,
        )
        item = Inventory(organization_id=organization.id, department_id=department.id,
                         event_id=event_record.id, item_name="Chair", quantity=10, unit="pcs")
        income = IncomeRecord(event_id=event_record.id, source="Donation", purpose="Supplies",
                              amount=100, received_on=date.today(), recorded_by=accounts["treasurer"].id)
        db.add_all([expense, item, income])
        db.flush()
        resources.append({"categories": category, "events": event_record, "expenses": expense,
                          "inventory": item, "incomes": income})
    roster = CiteMember(full_name="Officer", email=accounts["officer"].email, role="officer",
                        department_id=department.id, organization_id=organizations[0].id,
                        claimed_by_user_id=accounts["officer"].id)
    db.add(roster)
    db.commit()
    with TestClient(app) as client:
        def login(role):
            token = create_access_token(str(accounts[role].id))
            client.headers["Authorization"] = "Bearer " + token
            return token
        yield client, db, accounts, organizations, resources, login
    app.dependency_overrides.clear()
    app.dependency_overrides.update(original)
    db.close()
    engine.dispose()


@pytest.mark.parametrize("role", ["admin", "adviser", "treasurer", "officer"])
@pytest.mark.parametrize("module", ["categories", "events", "expenses", "inventory", "incomes"])
def test_lists_exclude_other_organization_in_same_department(system, role, module):
    client, db, users, orgs, resources, login = system
    login(role)
    response = client.get("/" + module)
    assert response.status_code == 200
    assert [row["id"] for row in response.json()] == [str(resources[0][module].id)]
    if module != "incomes":
        assert client.get(f"/{module}/{resources[1][module].id}").status_code == 403


def test_super_admin_sees_both_organizations_and_report_boundaries(system):
    client, db, users, orgs, resources, login = system
    login("super_admin")
    assert len(client.get("/events").json()) == 2
    login("officer")
    assert client.get(f"/reports/event/{resources[0]['events'].id}").status_code == 200
    assert client.get(f"/reports/event/{resources[1]['events'].id}").status_code == 403
    report = client.get("/reports/financial?period=school_year&school_year=2026-2027")
    assert report.status_code == 200
    assert [row["event_id"] for row in report.json()["events"]] == [str(resources[0]["events"].id)]


def test_officer_cannot_use_any_registered_operational_write_route(system):
    client, db, users, orgs, resources, login = system
    login("officer")
    checked = []
    for route in app.routes:
        if not isinstance(route, APIRoute) or route.path.startswith("/notifications") or (route.path.startswith("/auth/") and route.path not in
                                               ("/auth/register/admin", "/auth/register/sds")):
            continue
        for method in route.methods & {"POST", "PUT", "PATCH", "DELETE"}:
            path = route.path
            for parameter in route.param_convertors:
                path = path.replace("{" + parameter + "}", str(uuid4()))
            response = client.request(method, path, json={})
            assert response.status_code == 403, (method, path, response.text)
            checked.append((method, path))
    assert len(checked) >= 25


@pytest.mark.parametrize("role", ["adviser", "treasurer"])
def test_catalog_changes_require_administrator(system, role):
    client, db, users, orgs, resources, login = system
    login(role)
    assert client.post("/categories", json={"name": "New"}).status_code == 403
    assert client.patch(f"/inventory/{resources[0]['inventory'].id}", json={"item_name": "Changed"}).status_code == 403
    response = client.post(f"/inventory/{resources[0]['inventory'].id}/transactions", json={"change_qty": 1,
        "event_id": str(resources[0]["events"].id), "transaction_type": "donation", "reason": "Donated chair"})
    assert response.status_code == 201
    assert client.post(f"/inventory/{resources[0]['inventory'].id}/transactions",
                       json={"change_qty": 1, "event_id": str(resources[1]["events"].id),
                             "transaction_type": "donation", "reason": "Donated chair"}).status_code == 403


def test_admin_cannot_promote_to_admin_or_manage_other_organization(system):
    client, db, users, orgs, resources, login = system
    login("admin")
    endpoint = f"/users/{users['officer'].id}/access"
    assert client.patch(endpoint, json={"role": "admin"}).status_code == 403
    assert client.patch(endpoint, json={"organization_id": str(orgs[1].id)}).status_code == 403
    assert client.patch(f"/users/{users['super_admin'].id}/access", json={"is_suspended": True}).status_code == 403
    assert client.patch(f"/users/{users['admin'].id}/access", json={"is_suspended": True}).status_code == 403
    users["officer"].organization_id = orgs[1].id
    db.commit()
    assert client.patch(endpoint, json={"is_suspended": True}).status_code == 403


def test_role_change_updates_roster_and_existing_token_permissions(system):
    client, db, users, orgs, resources, login = system
    officer_token = login("officer")
    login("admin")
    endpoint = f"/users/{users['officer'].id}/access"
    assert client.patch(endpoint, json={"role": "treasurer"}).status_code == 200
    assert db.query(CiteMember).one().role == "treasurer"
    client.headers["Authorization"] = "Bearer " + officer_token
    payload = {"event_id": str(resources[0]["events"].id), "source": "Donation", "purpose": "Event", "amount": 10}
    assert client.post("/incomes", json=payload).status_code == 201
    login("admin")
    assert client.patch(endpoint, json={"role": "officer"}).status_code == 200
    client.headers["Authorization"] = "Bearer " + officer_token
    assert client.post("/incomes", json=payload).status_code == 403
    assert db.query(AuditLog).filter(AuditLog.action == "user.access_changed").count() == 2


def test_suspension_blocks_existing_token_and_registration_reactivation(system):
    client, db, users, orgs, resources, login = system
    officer_token = login("officer")
    login("admin")
    endpoint = f"/users/{users['officer'].id}/access"
    assert client.patch(endpoint, json={"is_suspended": True}).status_code == 200
    client.headers["Authorization"] = "Bearer " + officer_token
    assert client.get("/categories").status_code == 401
    assert client.post("/auth/verify-otp", json={"email": users["officer"].email, "otp_code": "123456"}).status_code == 403
    login("admin")
    assert client.patch(endpoint, json={"is_suspended": False}).status_code == 200
    client.headers["Authorization"] = "Bearer " + officer_token
    assert client.get("/categories").status_code == 200


def test_super_admin_transfer_does_not_transfer_historical_records(system):
    client, db, users, orgs, resources, login = system
    login("super_admin")
    response = client.patch(f"/users/{users['treasurer'].id}/access",
                            json={"organization_id": str(orgs[1].id)})
    assert response.status_code == 200
    login("treasurer")
    assert [row["id"] for row in client.get("/events").json()] == [str(resources[1]["events"].id)]
    assert client.get(f"/events/{resources[0]['events'].id}").status_code == 403


def test_self_review_is_blocked_for_admin_and_super_admin(system):
    client, db, users, orgs, resources, login = system
    event_record = resources[0]["events"]
    for role in ("admin", "super_admin"):
        event_record.proposed_by = users[role].id
        db.commit()
        login(role)
        response = client.post(f"/events/{event_record.id}/approve", json={})
        assert response.status_code == 403
        assert event_record.status == "pending"


def test_unassigned_account_and_sds_cannot_read_operational_data(system):
    client, db, users, orgs, resources, login = system
    users["admin"].organization_id = None
    db.commit()
    login("admin")
    assert client.get("/categories").status_code == 403
    login("sds_staff")
    assert client.get("/categories").status_code == 403
    assert client.get("/proposal-letters").status_code == 200
    assert client.post("/proposal-letters", json={}).status_code == 403


def test_audit_visibility_is_scoped_and_permissions_are_exposed(system):
    client, db, users, orgs, resources, login = system
    login("super_admin")
    for org in orgs:
        response = client.post("/cite-members", json={
            "full_name": org.name, "email": org.code + "@example.com", "role": "officer",
            "department_id": str(org.department_id), "organization_id": str(org.id),
        })
        assert response.status_code == 201
    assert len(client.get("/audit-logs").json()) == 2
    login("admin")
    logs = client.get("/audit-logs")
    assert logs.status_code == 200
    assert len(logs.json()) == 1
    assert logs.json()[0]["organization_id"] == str(orgs[0].id)
    login("officer")
    assert client.get("/audit-logs").status_code == 403
    assert client.get("/auth/permissions").json()["permissions"] == ["Read operational records, reports, and analytics"]


def test_admin_creation_validates_organization_before_provisioning(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    monkeypatch.setattr("app.services.account_provisioning.send_otp_email", lambda *a, **k: None)
    login("super_admin")
    response = client.post("/auth/register/admin", json={
        "full_name": "New Admin", "email": "new-admin@example.com",
        "department_id": str(orgs[0].department_id), "organization_id": str(orgs[0].id),
    })
    assert response.status_code == 201
    created = db.query(User).filter(User.email == "new-admin@example.com").one()
    assert created.organization_id == orgs[0].id
    assert created.must_change_password
    assert db.query(AuditLog).filter(AuditLog.action == "user.admin_created").count() == 1
