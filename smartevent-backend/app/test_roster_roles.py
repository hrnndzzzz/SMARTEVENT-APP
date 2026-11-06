"""Roster roles beyond members: Super Admin reach, and advisers inside their own organization."""

import uuid

import pytest

from app.models import AuditLog, Category, CiteMember, Inventory, User
from app.test_access_management import system  # noqa: F401
from app.test_roster_import import member, upload


def school_row(email, role):
    return member(email, **{"Role": role, "Department": None, "Organization Full Name": None})


def test_super_admin_imports_admin_sds_and_signatory(system):
    client, db, users, orgs, _, login = system
    login("super_admin")
    response = upload(client, [member("dean2@example.com", Role="Admin"),
                               school_row("sds2@example.com", "SDS Staff"),
                               school_row("sign2@example.com", "signatory")])
    assert response.status_code == 201, response.text
    stored = {m.email: m for m in db.query(CiteMember).filter(CiteMember.claimed_by_user_id.is_(None))}
    assert (stored["dean2@example.com"].role, stored["dean2@example.com"].organization_id) == ("admin", orgs[0].id)
    for email, role in (("sds2@example.com", "sds_staff"), ("sign2@example.com", "signatory")):
        assert (stored[email].role, stored[email].department_id, stored[email].organization_id) == (role, None, None)


@pytest.mark.parametrize("row", [member("dean2@example.com", Role="Admin"), school_row("sds2@example.com", "SDS Staff"),
                                 school_row("sign2@example.com", "Signatory")], ids=["admin", "sds", "signatory"])
def test_dean_cannot_import_school_roles(system, row):
    client, db, _, _, _, login = system
    login("admin")
    response = upload(client, [row])
    assert response.status_code == 422, response.text
    assert any(e["column"] == "Role" for e in response.json()["detail"]["errors"])
    assert db.query(CiteMember).count() == 1


def test_school_reviewer_row_must_leave_scope_blank(system):
    client, db, _, _, _, login = system
    login("super_admin")
    response = upload(client, [member("sds2@example.com", Role="SDS Staff")])
    assert response.status_code == 422, response.text
    assert {e["column"] for e in response.json()["detail"]["errors"]} == {"Department", "Organization Full Name"}


def test_adviser_imports_only_officers_and_treasurers_in_own_organization(system):
    client, db, _, _, _, login = system
    login("adviser")
    assert upload(client, [member(), member("t@example.com", Role="Treasurer")]).status_code == 201
    for row, column in ((member("b@example.com", **{"Organization Full Name": "Organization B"}), "Organization Full Name"),
                        (member("a@example.com", Role="Adviser"), "Role")):
        response = upload(client, [row])
        assert response.status_code == 422, response.text
        assert any(e["column"] == column for e in response.json()["detail"]["errors"])
    assert db.query(CiteMember).count() == 3


def test_adviser_roster_form_is_limited(system):
    client, db, users, orgs, _, login = system
    login("adviser")
    ok = client.post("/cite-members", json={"full_name": "O", "email": "o@example.com", "role": "officer"})
    assert ok.status_code == 201, ok.text
    assert ok.json()["organization_id"] == str(orgs[0].id)
    assert client.post("/cite-members", json={"full_name": "A", "email": "a@example.com", "role": "adviser"}).status_code == 403
    assert client.patch(f"/cite-members/{ok.json()['id']}", json={"role": "adviser"}).status_code == 403
    assert client.post("/cite-members", json={"full_name": "B", "email": "b@example.com", "role": "officer",
                                              "organization_id": str(orgs[1].id)}).status_code == 403


def test_super_admin_adds_sds_roster_entry_without_scope(system):
    client, db, _, orgs, _, login = system
    login("super_admin")
    response = client.post("/cite-members", json={"full_name": "S", "email": "s@example.com", "role": "sds_staff"})
    assert response.status_code == 201, response.text
    assert (response.json()["department_id"], response.json()["organization_id"]) == (None, None)
    assert client.post("/cite-members", json={"full_name": "S", "email": "s2@example.com", "role": "sds_staff",
                                              "organization_id": str(orgs[0].id)}).status_code == 422


@pytest.mark.parametrize("role", ["admin", "sds_staff", "signatory"])
def test_super_admin_promotes_roster_account(system, role):
    client, db, users, orgs, _, login = system
    adviser = users["adviser"]
    db.add(CiteMember(full_name="Adviser", email=adviser.email, role="adviser", department_id=adviser.department_id,
                      organization_id=adviser.organization_id, claimed_by_user_id=adviser.id))
    db.commit()
    login("super_admin")
    response = client.patch(f"/users/{adviser.id}/access", json={"role": role})
    assert response.status_code == 200, response.text
    entry = db.query(CiteMember).filter_by(claimed_by_user_id=adviser.id).one()
    db.refresh(entry)
    school = role != "admin"
    assert entry.role == role
    assert (entry.organization_id is None, entry.department_id is None) == (school, school)


def test_adviser_manages_officer_and_treasurer_accounts_only(system):
    client, db, users, orgs, _, login = system
    peer = User(full_name="Peer", email="peer@example.com", password_hash="unused", role="adviser", is_active=True,
                must_change_password=False, department_id=orgs[0].department_id, organization_id=orgs[0].id)
    db.add(peer)
    db.commit()
    login("adviser")
    officer = users["officer"]
    assert client.patch(f"/users/{officer.id}/access", json={"role": "treasurer"}).status_code == 200
    assert client.patch(f"/users/{officer.id}/access", json={"role": "adviser"}).status_code == 403
    assert client.patch(f"/users/{peer.id}/access", json={"is_suspended": True}).status_code == 403
    assert client.patch(f"/users/{officer.id}/access", json={"organization_id": str(orgs[1].id)}).status_code == 403


def test_adviser_catalog_and_audit_stay_in_own_organization(system):
    client, db, users, orgs, resources, login = system
    login("adviser")
    created = client.post("/categories", json={"name": "Food", "allocated_budget": 100})
    assert created.status_code == 201, created.text
    assert db.get(Category, uuid.UUID(created.json()["id"])).organization_id == orgs[0].id
    assert client.patch(f"/categories/{resources[1]['categories'].id}", json={"name": "X"}).status_code == 403
    assert client.delete(f"/inventory/{resources[1]['inventory'].id}").status_code == 403
    db.add(AuditLog(user_id=users["admin"].id, action="other.org", entity_type="x", entity_id=orgs[1].id,
                    organization_id=orgs[1].id, department_id=orgs[1].department_id))
    db.commit()
    logs = client.get("/audit-logs")
    assert logs.status_code == 200, logs.text
    assert "other.org" not in {row["action"] for row in logs.json()}
    assert db.query(Inventory).count() == 2  # the other organization's item was not deleted


def test_sds_roster_entry_self_registers_and_verifies(system, monkeypatch):
    client, db, *_ = system
    monkeypatch.setattr("app.services.account_provisioning.send_otp_email", lambda *a, **k: None)
    monkeypatch.setattr("app.services.account_provisioning.generate_otp_code", lambda: "123456")
    monkeypatch.setattr("app.services.notifications.send_email", lambda *a, **k: None)
    db.add(CiteMember(full_name="Reviewer", email="rev@example.com", role="sds_staff"))
    db.commit()
    assert client.post("/auth/register", json={"email": "rev@example.com", "password": "Password123!"}).status_code == 201
    response = client.post("/auth/verify-otp", json={"email": "rev@example.com", "otp_code": "123456"})
    assert response.status_code == 200, response.text
    user = db.query(User).filter_by(email="rev@example.com").one()
    assert (user.role, user.is_active, user.department_id, user.organization_id) == ("sds_staff", True, None, None)
