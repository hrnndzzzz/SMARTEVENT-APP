"""Position capabilities and Dean scope, exercised through real isolated routes."""

import pytest
from datetime import date

from app.models import AuditLog, CiteMember, Department, Event, EventProposalLetter, Organization
from app.test_access_management import system
from app.test_file_access import signer


def proposal(org, **changes):
    return {
        "title": "Officer proposal", "school_year": "2026-2027", "semester": "1st",
        "event_scope": "organizational", "organization_id": str(org.id),
        "department_id": str(org.department_id), **changes,
    }


def officer_position(system, position):
    client, db, users, orgs, resources, login = system
    users["officer"].position = position
    db.commit()
    login("officer")


@pytest.mark.parametrize("position", ["President", "Vice President", "Secretary", "  pReSiDeNt  ", " vice   PRESIDENT ", "\tSECRETARY\n"])
def test_lead_officers_can_manage_own_proposal_and_complete_review(system, position):
    client, db, users, orgs, resources, login = system
    officer_position(system, position)
    created = client.post("/events", json=proposal(orgs[0], category_id=str(resources[0]["categories"].id)))
    assert created.status_code == 201, created.text
    path = "/events/" + created.json()["id"]
    assert created.json()["proposed_by"] == str(users["officer"].id)
    login("admin")
    assert client.put(path + "/routing", json={"signatory_ids": [str(users["signatory"].id)]}).status_code == 200
    assert client.put(path + "/logistics", json={"activity_location": "on_campus", "destination": "Campus", "transport_mode": "none"}).status_code == 200
    login("officer")
    assert client.patch(path, json={"title": "Revised proposal"}).status_code == 200
    assert client.post(path + "/submit").json()["status"] == "pending_adviser"
    assert client.patch(path, json={"title": "Too late"}).status_code == 409
    assert client.delete(path).status_code == 409
    assert client.post(path + "/approve", json={}).status_code == 403
    login("adviser")
    assert client.post(path + "/reject", json={"remarks": "Revise"}).status_code == 200
    login("officer")
    assert client.patch(path, json={"title": "Corrected proposal"}).status_code == 200
    assert client.post(path + "/submit").json()["status"] == "pending_adviser"
    login("adviser")
    assert client.post(path + "/approve", json={}).json()["status"] == "pending_admin"
    login("admin")
    assert client.post(path + "/approve", json={}).json()["status"] == "pending_institutional_review"
    login("signatory")
    assert client.post(path + "/approve", json={}).json()["status"] == "approved"
    login("admin")
    assert [row["decision"] for row in client.get(path + "/approvals").json()] == [
        "rejected", "resubmitted", "approved", "approved", "approved",
    ]


@pytest.mark.parametrize("position", [None, "", "Auditor", "PRO", "Head of Creatives", "1st year representative", "Assistant Secretary", "Moderator", "Treasurer"])
def test_other_officer_positions_cannot_propose(system, position):
    client, db, users, orgs, resources, login = system
    officer_position(system, position)
    assert client.post("/events", json=proposal(orgs[0])).status_code == 403
    assert client.get("/events").status_code == 200


def test_officer_proposal_permissions_do_not_allow_other_owners_or_organizations(system):
    client, db, users, orgs, resources, login = system
    officer_position(system, "President")
    assert client.post("/events", json=proposal(orgs[1])).status_code == 403
    for index in (0, 1):
        record = resources[index]["events"]
        record.status = "draft"
        db.commit()
        path = f"/events/{record.id}"
        assert client.patch(path, json={"title": "Hijack"}).status_code == 403
        assert client.post(path + "/submit").status_code == 403
        assert client.delete(path).status_code == 403
    created = client.post("/events", json=proposal(orgs[0], status="pending"))
    assert created.status_code == 201, created.text
    assert created.json()["status"] == "pending_adviser"
    assert client.post(f"/events/{created.json()['id']}/reject", json={}).status_code == 403
    draft = client.post("/events", json=proposal(orgs[0]))
    assert client.delete(f"/events/{draft.json()['id']}").status_code == 204


@pytest.mark.parametrize("position", ["President", "Vice President", "Secretary"])
def test_lead_officers_still_cannot_write_other_modules(system, position):
    client, db, users, orgs, resources, login = system
    officer_position(system, position)
    requests = [
        ("POST", "/categories"), ("PATCH", f"/inventory/{resources[0]['inventory'].id}"),
        ("POST", f"/inventory/{resources[0]['inventory'].id}/transactions"),
        ("POST", "/cite-members"), ("PATCH", f"/users/{users['treasurer'].id}/access"),
        ("POST", f"/events/{resources[0]['events'].id}/approve"),
        ("PATCH", f"/events/{resources[0]['events'].id}/academic-metadata"),
    ]
    for method, path in requests:
        assert client.request(method, path, json={}).status_code == 403, path


def test_officer_letters_are_limited_to_owned_editable_proposals(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    monkeypatch.setattr("app.routers.proposal_letters.upload_proposal_letter", lambda *a: "https://example.com/letter.pdf")
    officer_position(system, "Secretary")
    created = client.post("/events", json=proposal(orgs[0]))
    assert created.status_code == 201, created.text
    event_id = created.json()["id"]

    def upload(target):
        return client.post("/proposal-letters", data={"event_id": str(target), "title": "Proposal letter"},
                           files={"file": ("letter.pdf", b"%PDF-1.4 test\n%%EOF", "application/pdf")})

    response = upload(event_id)
    assert response.status_code == 201, response.text
    letter_id = response.json()["id"]
    assert client.get(f"/proposal-letters/{letter_id}").status_code == 200
    for record in (resources[0]["events"], resources[1]["events"]):
        assert upload(record.id).status_code == 403
        foreign_letter = EventProposalLetter(event_id=record.id, title="Other owner's letter",
                                             document_url="https://example.com/other.pdf", submitted_by=users["treasurer"].id)
        db.add(foreign_letter)
        db.commit()
        assert client.get(f"/proposal-letters/{foreign_letter.id}").status_code == 403
    assert [row["id"] for row in client.get("/proposal-letters").json()] == [letter_id]
    assert client.post(f"/events/{event_id}/submit").status_code == 200
    assert upload(event_id).status_code == 409
    assert client.get(f"/proposal-letters/{letter_id}").status_code == 200


@pytest.mark.parametrize("role", ["admin", "super_admin", "adviser", "officer", "sds_staff"])
def test_non_treasurers_cannot_execute_any_financial_write(system, role):
    client, db, users, orgs, resources, login = system
    users[role].position = "Treasurer" if role != "officer" else "President"
    db.commit()
    login(role)
    expense_id = resources[0]["expenses"].id
    requests = [
        ("POST", "/incomes"), ("POST", "/expenses"), ("PATCH", f"/expenses/{expense_id}"),
        ("DELETE", f"/expenses/{expense_id}"), ("POST", f"/expenses/{expense_id}/parse-receipt"),
        ("POST", f"/expenses/{expense_id}/receipt"), ("POST", "/expenses/scan-receipt"),
        ("POST", f"/expenses/{expense_id}/complete-purchase"),
        ("POST", "/receipts"), ("POST", f"/receipts/{expense_id}/upload"),
    ]
    for method, path in requests:
        result = client.request(method, path, json={})
        assert result.status_code == 403, (method, path, result.text)


@pytest.mark.parametrize("role", ["admin", "super_admin", "adviser"])
def test_financial_viewing_and_review_are_preserved(system, role):
    client, db, users, orgs, resources, login = system
    login(role)
    assert client.get("/incomes").status_code == 200
    assert client.get("/expenses").status_code == 200
    expense = resources[0]["expenses"]
    assert client.post(f"/expenses/{expense.id}/approve", json={}).status_code == 200


def test_dean_reads_all_department_organizations_and_creates_in_selected_organization(system):
    client, db, users, orgs, resources, login = system
    login("admin")
    for module in ("events", "expenses", "categories", "inventory", "incomes"):
        assert {row["id"] for row in client.get("/" + module).json()} == {str(r[module].id) for r in resources}
    assert {row["id"] for row in client.get("/organizations").json()} == {str(o.id) for o in orgs}
    response = client.post("/events", json=proposal(orgs[1], category_id=str(resources[1]["categories"].id)))
    assert response.status_code == 201, response.text
    assert response.json()["organization_id"] == str(orgs[1].id)
    default = proposal(orgs[0])
    del default["organization_id"]
    response = client.post("/events", json=default)
    assert response.status_code == 201
    assert response.json()["organization_id"] == str(orgs[0].id)
    event = resources[1]["events"]
    event.status = "pending_admin"
    db.commit()
    assert client.put(f"/events/{event.id}/routing", json={"signatory_ids": [str(users["signatory"].id)]}).status_code == 200
    assert client.post(f"/events/{event.id}/approve", json={}).status_code == 200
    assert client.get(f"/reports/event/{event.id}").status_code == 200


def test_dean_roster_member_management_and_audit_cover_department(system):
    client, db, users, orgs, resources, login = system
    users["officer"].organization_id = orgs[1].id
    db.commit()
    login("admin")
    assert str(users["officer"].id) in {row["id"] for row in client.get("/users").json()}
    result = client.patch(f"/users/{users['officer'].id}/access", json={"position": "President"})
    assert result.status_code == 200, result.text
    member = client.post("/cite-members", json={"full_name": "Moderator B", "email": "moderator-b@example.com",
        "role": "adviser", "position": "Moderator", "organization_id": str(orgs[1].id)})
    assert member.status_code == 201, member.text
    assert client.patch(f"/cite-members/{member.json()['id']}", json={"position": "Adviser"}).status_code == 200
    assert len(client.get("/cite-members").json()) == 2
    assert len(client.get("/cite-members", params={"organization_id": str(orgs[1].id)}).json()) == 2
    assert len(client.get("/audit-logs").json()) == 3


def test_dean_cannot_cross_department_or_select_foreign_organization(system):
    client, db, users, orgs, resources, login = system
    department = Department(code="OTHER", name="Other department")
    db.add(department)
    db.flush()
    organization = Organization(code="OTHER", name="Other organization", department_id=department.id)
    db.add(organization)
    db.flush()
    event = Event(title="Foreign event", department_id=department.id, organization_id=organization.id,
                  proposed_by=users["treasurer"].id, school_year="2026-2027", semester="1st", event_scope="organizational")
    db.add(event)
    db.commit()
    login("admin")
    assert str(event.id) not in {row["id"] for row in client.get("/events").json()}
    assert client.get(f"/events/{event.id}").status_code == 403
    assert client.post("/events", json=proposal(organization)).status_code == 403
    invalid = proposal(orgs[0], organization_id=str(organization.id))
    assert client.post("/events", json=invalid).status_code in (400, 403)
    for path in ("/users", "/cite-members"):
        assert client.get(path, params={"organization_id": str(organization.id)}).status_code == 403


def test_position_change_updates_roster_audit_and_existing_token_capabilities(system):
    client, db, users, orgs, resources, login = system
    token = login("officer")
    assert client.get("/auth/permissions").json().get("can_propose_events") is False
    login("admin")
    path = f"/users/{users['officer'].id}/access"
    assert client.patch(path, json={"position": "President"}).status_code == 200
    assert db.query(CiteMember).one().position == "President"
    audit = db.query(AuditLog).filter(AuditLog.action == "user.access_changed").one()
    assert audit.details["before"]["position"] is None
    assert audit.details["after"]["position"] == "President"
    client.headers["Authorization"] = "Bearer " + token
    permissions = client.get("/auth/permissions").json()
    assert permissions["position"] == "President"
    assert permissions["can_propose_events"] is True
    assert permissions["can_record_finance"] is False
    created = client.post("/events", json=proposal(orgs[0]))
    assert created.status_code == 201, created.text
    login("admin")
    assert client.patch(path, json={"position": "Auditor"}).status_code == 200
    client.headers["Authorization"] = "Bearer " + token
    assert client.get("/auth/permissions").json()["can_propose_events"] is False
    assert client.post(f"/events/{created.json()['id']}/submit").status_code == 403
    assert client.post("/auth/register", json={"email": users["officer"].email, "password": "some-password", "position": "President"}).status_code != 201


def test_unclaimed_roster_position_change_audits_previous_and_resulting_permissions(system):
    client, db, users, orgs, resources, login = system
    login("admin")
    created = client.post("/cite-members", json={
        "full_name": "Future President", "email": "future-president@example.com",
        "role": "officer", "position": "Auditor",
    })
    assert created.status_code == 201, created.text
    response = client.patch(f"/cite-members/{created.json()['id']}", json={"position": "President"})
    assert response.status_code == 200, response.text
    audit = db.query(AuditLog).filter(AuditLog.action == "roster.updated").one()
    assert audit.details["before"]["position"] == "Auditor"
    assert audit.details["after"]["position"] == "President"
    assert audit.details["after"]["role"] == "officer"


def test_owned_draft_with_letter_returns_conflict_and_preserves_records(system):
    client, db, users, orgs, resources, login = system
    officer_position(system, "President")
    event = resources[0]["events"]
    event.status = "draft"
    event.proposed_by = users["officer"].id
    letter = EventProposalLetter(event_id=event.id, title="Existing proposal letter",
                                 document_url="https://example.com/letter.pdf", submitted_by=users["officer"].id)
    db.add(letter)
    db.commit()
    path = f"/events/{event.id}"
    response = client.delete(path)
    assert response.status_code == 409, response.text
    assert client.get(path).status_code == 200
    assert client.get(f"/proposal-letters/{letter.id}").status_code == 200


@pytest.mark.parametrize("role,position,propose,finance", [
    ("adviser", "Moderator", True, False), ("adviser", "Adviser", True, False),
    ("treasurer", "Treasurer", True, True), ("admin", "Dean", True, False),
    ("super_admin", None, True, False), ("sds_staff", "President", False, False),
])
def test_permissions_describe_effective_capabilities(system, role, position, propose, finance):
    client, db, users, orgs, resources, login = system
    users[role].position = position
    db.commit()
    login(role)
    result = client.get("/auth/permissions")
    assert result.status_code == 200
    data = result.json()
    assert data["role"] == role
    assert data["position"] == position
    assert data["can_propose_events"] is propose
    assert data["can_record_finance"] is finance


@pytest.mark.parametrize("position", ["President", "Vice President", "Secretary"])
def test_lead_officers_can_prepare_and_submit_owned_sap_without_sds_powers(system, monkeypatch, position):
    from app.config import settings
    from app.test_sap import fixture_data

    client, db, users, orgs, resources, login = system
    event = resources[0]["events"]
    event.status, event.proposed_by = "draft", users["officer"].id
    event.allocated_budget = event.remaining_budget = 2500
    officer_position(system, position)
    monkeypatch.setattr(settings, "sap_verification_base_url", "https://example.org/sap/verify")
    monkeypatch.setattr("app.services.sap.institution_today", lambda: date(2026, 9, 27))
    base = f"/events/{event.id}/sap-proposal"
    created = client.post(base)
    assert created.status_code == 201, created.text

    def version():
        return client.get(base).json()["version"]

    data = fixture_data()
    response = client.patch(base, json={"expected_version": version(), "details": data["details"]})
    assert response.status_code == 200, response.text
    for collection, items in data["collections"].items():
        response = client.put(base + "/" + collection, json={"expected_version": version(), "items": items})
        assert response.status_code == 200, response.text
    assert client.put(base + "/sds-clearance", json={"expected_version": version(), "clearance": data["clearance"]}).status_code == 403
    login("sds_staff")
    response = client.put(base + "/sds-clearance", json={"expected_version": version(), "clearance": data["clearance"]})
    assert response.status_code == 200, response.text
    login("officer")
    response = client.post(base + "/submit", json={"expected_version": version()})
    assert response.status_code == 200, response.text
    assert response.json()["state"] == "pending_sap_review"
    assert client.patch(base, json={"expected_version": version(), "details": data["details"]}).status_code == 409


def test_lead_officer_prepares_colleagues_sap_only_in_own_organization(system):
    client, db, users, orgs, resources, login = system
    for resource in resources:
        resource["events"].status = "draft"
    officer_position(system, "President")
    assert client.post(f"/events/{resources[1]['events'].id}/sap-proposal").status_code == 403
    assert client.post(f"/events/{resources[0]['events'].id}/sap-proposal").status_code == 201


def test_lead_officer_private_letter_access_is_owner_only(system, signer):
    from app.config import settings
    client, db, users, orgs, resources, login = system
    resources[0]["events"].proposed_by = users["officer"].id
    references = []
    for index in (0, 1):
        if index == 1:
            resources[index]["events"].organization_id = orgs[0].id
        url = f"{settings.supabase_url}/storage/v1/object/proposal-letters/{orgs[0].id}/{users['officer'].id}/{index}.pdf"
        references.append(url)
        db.add(EventProposalLetter(event_id=resources[index]["events"].id, title="Private letter",
                                   document_url=url, submitted_by=users["officer"].id))
    officer_position(system, "President")
    own = client.get("/files", params={"reference": references[0]})
    assert own.status_code == 200, own.text
    assert client.get("/files", params={"reference": references[1]}).status_code == 404


def test_dean_roster_import_accepts_other_cite_organizations_and_rejects_other_departments(system):
    from app.test_roster_import import member, upload
    client, db, users, orgs, resources, login = system
    login("admin")
    response = upload(client, [member("other-org@example.com", **{"Organization Full Name": "Organization B"})])
    assert response.status_code == 201, response.text
    department = Department(code="EXTERNAL", name="External")
    db.add(department)
    db.flush()
    db.add(Organization(code="EXTERNAL", name="External Organization", department_id=department.id))
    db.commit()
    response = upload(client, [member("external@example.com", **{"Department": "External", "Organization Full Name": "External Organization"})])
    assert response.status_code == 422, response.text
    assert db.query(CiteMember).filter_by(email="external@example.com").first() is None
