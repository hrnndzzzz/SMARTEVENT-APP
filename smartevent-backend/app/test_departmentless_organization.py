"""Organizations outside any department, the department failsafe, and per-organization reports."""

import pytest
from fastapi import HTTPException

from app.models import CiteMember, Event, Organization
from app.models_sap import SAPProposal
from app.services.notifications import check_registration_assignment
from app.test_access_management import system
from app.test_sap import fixture_data, sap_system, send


def no_department(db, users, orgs, resources):
    """Organization A leaves its department; its Admin, who needs one, moves to B."""
    orgs[0].department_id = None
    for role in ("adviser", "treasurer", "officer"):
        users[role].department_id = None
    users["admin"].organization_id = orgs[1].id
    for record in resources[0].values():
        if hasattr(record, "department_id"):
            record.department_id = None
    db.query(CiteMember).update({CiteMember.department_id: None})
    db.commit()


def test_a_super_admin_adds_an_organization_with_no_department(system):
    client, db, users, orgs, resources, login = system
    login("super_admin")
    created = client.post("/organizations", json={"code": "jpssite", "name": "JPSSITE"})
    assert created.status_code == 201, created.text
    assert created.json()["department_id"] is None and created.json()["code"] == "JPSSITE"
    login("admin")
    assert client.post("/organizations", json={"code": "X", "name": "X"}).status_code == 403


def test_a_blank_department_is_refused_beside_an_organization_that_has_one(system):
    client, db, users, orgs, resources, login = system
    loose = Organization(code="LOOSE", name="Loose")
    db.add(loose)
    db.commit()
    login("super_admin")
    entry = {"full_name": "New member", "role": "officer"}
    refused = client.post("/cite-members", json={**entry, "email": "a@example.com", "organization_id": str(orgs[1].id)})
    assert refused.status_code == 400
    assert refused.json()["detail"] == "This organization belongs to a department. Select it."
    added = client.post("/cite-members", json={**entry, "email": "b@example.com", "organization_id": str(loose.id)})
    assert added.status_code == 201, added.text
    assert added.json()["department_id"] is None
    mismatched = client.post("/cite-members", json={**entry, "email": "c@example.com", "organization_id": str(loose.id),
                                                    "department_id": str(orgs[1].department_id)})
    assert mismatched.status_code == 400
    admin = client.post("/cite-members", json={**entry, "role": "admin", "email": "d@example.com", "organization_id": str(loose.id)})
    assert admin.status_code == 422


def test_registration_needs_the_organizations_own_department(system):
    client, db, users, orgs, resources, login = system
    loose = Organization(code="LOOSE", name="Loose")
    db.add(loose)
    db.flush()
    with pytest.raises(HTTPException):
        check_registration_assignment(db, CiteMember(role="officer", organization_id=orgs[0].id, department_id=None))
    check_registration_assignment(db, CiteMember(role="officer", organization_id=loose.id, department_id=None))
    with pytest.raises(HTTPException):
        check_registration_assignment(db, CiteMember(role="admin", organization_id=loose.id, department_id=None))


def test_an_account_missing_its_organizations_department_is_locked_out(system):
    client, db, users, orgs, resources, login = system
    users["officer"].department_id = None
    db.commit()
    login("officer")
    response = client.get("/events")
    assert response.status_code == 403
    assert "assign your department" in response.json()["detail"]


def test_a_member_of_an_organization_with_no_department_sees_only_its_own(system):
    client, db, users, orgs, resources, login = system
    no_department(db, users, orgs, resources)
    other = Organization(code="OTHER", name="Other")
    db.add(other)
    db.flush()
    db.add(Event(organization_id=other.id, title="Not yours", proposed_by=users["super_admin"].id, status="draft"))
    db.commit()
    login("treasurer")
    for module in ("events", "categories", "expenses", "inventory"):
        rows = client.get("/" + module)
        assert rows.status_code == 200, (module, rows.text)
        assert [row["id"] for row in rows.json()] == [str(resources[0][module].id)], module
    assert client.get(f"/events/{resources[1]['events'].id}").status_code == 403
    login("admin")
    assert str(resources[0]["events"].id) not in [row["id"] for row in client.get("/events").json()]


def test_with_no_department_the_moderator_sends_it_straight_to_the_sds_office(sap_system, system):
    client, db, users, event, login, base = sap_system
    _, _, _, orgs, resources, _ = system
    no_department(db, users, orgs, resources)
    data = fixture_data()
    data["details"]["department"] = ""
    sent = send(sap_system, data)
    assert sent["state"] == "pending_department_review" and event.status == "pending_adviser"
    login("adviser")
    approved = client.post(f"/events/{event.id}/approve", json={})
    assert approved.status_code == 200, approved.text
    assert approved.json()["status"] == "pending_institutional_review"
    assert db.query(SAPProposal).one().state == "pending_sap_review"
    login("sds_staff")
    steps = client.get(base + "/workflow").json()["steps"]
    assert steps[2]["position"] == "Dean (not applicable: no department)"


def test_a_departmental_proposal_still_names_its_department(sap_system):
    client, db, users, event, login, base = sap_system
    data = fixture_data()
    data["details"]["department"] = ""
    login("treasurer")
    version = client.get(base).json()["version"]
    assert client.patch(base, json={"expected_version": version, "details": data["details"]}).status_code == 200
    for key, items in data["collections"].items():
        version = client.get(base).json()["version"]
        assert client.put(base + "/" + key, json={"expected_version": version, "items": items}).status_code == 200
    refused = client.post(base + "/submit", json={"expected_version": client.get(base).json()["version"]})
    assert refused.status_code == 422
    assert "department" in refused.text


def test_reports_narrow_to_one_organization_but_never_widen(system):
    client, db, users, orgs, resources, login = system
    login("admin")
    everything = client.get("/analytics/dashboard").json()
    only_b = client.get(f"/analytics/dashboard?organization_id={orgs[1].id}").json()
    assert everything["total_categories"] == 2 and only_b["total_categories"] == 1
    report = client.get(f"/reports/financial?period=school_year&school_year=2026-2027&organization_id={orgs[1].id}")
    assert [row["event_id"] for row in report.json()["events"]] == [str(resources[1]["events"].id)]
    export = client.get(f"/reports/dashboard/export?format=csv&organization_id={orgs[1].id}")
    assert export.status_code == 200
    login("adviser")  # Organization A's
    assert client.get(f"/analytics/dashboard?organization_id={orgs[1].id}").json()["total_categories"] == 0
    report = client.get(f"/reports/financial?period=school_year&school_year=2026-2027&organization_id={orgs[1].id}")
    assert report.json()["events"] == []
