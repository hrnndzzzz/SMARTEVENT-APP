from datetime import datetime, timezone

import pytest
from sqlalchemy.exc import IntegrityError

from app.models import (
    Approval, AuditLog, DocumentRouting, EventParticipant, EventProposalLetter,
    EventRequirement, RequirementPreset, StudentComplianceRecord, User,
)
from app.security import hash_password
from app.services.event_routing import INSTITUTIONAL_REVIEW
from app.test_access_management import system


def configure(system, *, two=False):
    client, db, users, orgs, resources, login = system
    ids = [str(users["signatory"].id)]
    if two:
        second = User(full_name="Second signatory", email="second@example.com", password_hash="unused",
                      role="signatory", is_active=True, must_change_password=False)
        db.add(second)
        db.commit()
        users["second"] = second
        ids.append(str(second.id))
    login("admin")
    path = f"/events/{resources[0]['events'].id}"
    result = client.put(path + "/routing", json={"signatory_ids": ids})
    assert result.status_code == 200, result.text
    return path, ids


def send_to_institution(system, *, two=False):
    path, ids = configure(system, two=two)
    client, db, users, orgs, resources, login = system
    login("adviser")
    assert client.post(path + "/approve", json={}).status_code == 200
    login("admin")
    result = client.post(path + "/approve", json={})
    assert result.status_code == 200, result.text
    assert result.json()["status"] == INSTITUTIONAL_REVIEW
    return path, ids


def test_sequential_signing_and_current_round_visibility(system):
    client, db, users, orgs, resources, login = system
    path, ids = send_to_institution(system, two=True)
    login("second")
    assert client.get("/events").json()[0]["id"] == str(resources[0]["events"].id)
    for action in ("approve", "reject"):
        assert client.post(path + "/" + action, json={}).status_code == 409
    login("signatory")
    first = client.post(path + "/approve", json={"remarks": "First signed"})
    assert first.status_code == 200, first.text
    assert first.json()["status"] == INSTITUTIONAL_REVIEW
    assert client.post(path + "/approve", json={}).status_code == 409
    login("second")
    assert client.post(path + "/approve", json={}).json()["status"] == "approved"
    assert client.get(path).status_code == 403
    assert client.get("/events").json() == []
    login("admin")
    routing = client.get(path + "/routing").json()
    assert [row["status"] for row in routing] == ["approved", "approved"]
    assert [row["signatory_id"] for row in routing] == ids
    assert db.query(AuditLog).filter(AuditLog.action == "event.institutional_reviewed").count() == 2


def test_rejection_resubmission_preserves_old_decisions(system):
    client, db, users, orgs, resources, login = system
    path, ids = send_to_institution(system, two=True)
    login("signatory")
    assert client.post(path + "/approve", json={}).status_code == 200
    login("second")
    rejected = client.post(path + "/reject", json={"remarks": "Revise itinerary"})
    assert rejected.json()["status"] == "rejected"
    login("treasurer")
    assert client.patch(path, json={"description": "Revised itinerary"}).status_code == 200
    resubmitted = client.post(path + "/submit")
    assert resubmitted.status_code == 200, resubmitted.text
    assert resubmitted.json()["review_round"] == 2
    assert resubmitted.json()["status"] == "pending_adviser"
    login("admin")
    history = client.get(path + "/routing").json()
    assert [row["status"] for row in history] == ["approved", "rejected", "pending", "pending"]
    assert [row["review_round"] for row in history] == [1, 1, 2, 2]
    assert client.put(path + "/routing", json={"signatory_ids": ids[:1]}).status_code == 200
    assert db.query(DocumentRouting).filter(DocumentRouting.review_round == 1).count() == 2
    login("adviser")
    assert client.post(path + "/approve", json={}).status_code == 200
    login("admin")
    assert client.post(path + "/approve", json={}).status_code == 200
    login("second")
    assert client.get(path).status_code == 403
    assert client.post(path + "/approve", json={}).status_code == 403
    login("signatory")
    assert client.post(path + "/approve", json={}).json()["status"] == "approved"
    assert db.query(Approval).filter(Approval.decision == "resubmitted").count() == 1


@pytest.mark.parametrize("role", ["admin", "super_admin", "adviser"])
def test_operational_reviewers_cannot_bypass_institutional_stage(system, role):
    path, _ = send_to_institution(system)
    client, db, users, orgs, resources, login = system
    login(role)
    for action in ("approve", "reject"):
        assert client.post(path + "/" + action, json={}).status_code == 409
    assert resources[0]["events"].status == INSTITUTIONAL_REVIEW


def test_missing_route_blocks_admin_review_without_recording_a_decision(system):
    client, db, users, orgs, resources, login = system
    resources[0]["events"].status = "pending_admin"
    db.commit()
    login("admin")
    assert client.post(f"/events/{resources[0]['events'].id}/approve", json={}).status_code == 409
    assert db.query(Approval).count() == 0


@pytest.mark.parametrize("field,value", [("is_suspended", True), ("is_active", False),
                                         ("must_change_password", True), ("role", "sds_staff")])
def test_unavailable_signatory_blocks_routing_and_advancement(system, field, value):
    path, ids = configure(system)
    client, db, users, orgs, resources, login = system
    setattr(users["signatory"], field, value)
    resources[0]["events"].status = "pending_admin"
    db.commit()
    assert client.put(path + "/routing", json={"signatory_ids": ids}).status_code == 409
    assert client.post(path + "/approve", json={}).status_code == 409
    assert resources[0]["events"].status == "pending_admin"


@pytest.mark.parametrize("role", ["adviser", "treasurer", "officer", "sds_staff", "signatory"])
def test_only_admin_can_configure_routing_or_list_signatories(system, role):
    client, db, users, orgs, resources, login = system
    login(role)
    assert client.get("/users/signatories").status_code == 403
    response = client.put(f"/events/{resources[0]['events'].id}/routing",
                          json={"signatory_ids": [str(users["signatory"].id)]})
    assert response.status_code == 403


def test_route_validation_and_cross_organization_denial(system):
    path, ids = configure(system)
    client, db, users, orgs, resources, login = system
    assert client.put(path + "/routing", json={"signatory_ids": []}).status_code == 422
    assert client.put(path + "/routing", json={"signatory_ids": ids * 2}).status_code == 422
    assert client.put(path + "/routing", json={"signatory_ids": [str(users["admin"].id)]}).status_code == 409
    assert client.put(f"/events/{resources[1]['events'].id}/routing", json={"signatory_ids": ids}).status_code == 403
    resources[0]["events"].proposed_by = users["signatory"].id
    db.commit()
    assert client.put(path + "/routing", json={"signatory_ids": ids}).status_code == 403


def test_routing_frozen_during_review_and_self_review_still_blocked(system):
    path, ids = send_to_institution(system)
    client, db, users, orgs, resources, login = system
    assert client.put(path + "/routing", json={"signatory_ids": ids}).status_code == 409
    resources[0]["events"].proposed_by = users["signatory"].id
    db.commit()
    login("signatory")
    for action in ("approve", "reject"):
        assert client.post(path + "/" + action, json={}).status_code == 403


@pytest.mark.parametrize("path", ["/categories", "/expenses", "/incomes", "/inventory", "/analytics/dashboard",
    "/reports/financial?period=monthly", "/users", "/audit-logs", "/events/requirement-presets"])
def test_signatory_has_no_general_operational_access(system, path):
    client, db, users, orgs, resources, login = system
    login("signatory")
    assert client.get(path).status_code == 403


def test_signatory_can_only_read_assigned_event_letters_and_private_files(system, monkeypatch):
    path, _ = send_to_institution(system)
    client, db, users, orgs, resources, login = system
    from app.config import settings
    monkeypatch.setattr(settings, "supabase_url", "https://test.supabase.co")
    for index, resource in enumerate(resources):
        db.add(EventProposalLetter(event_id=resource["events"].id, title=f"Letter {index}",
            document_url=f"https://test.supabase.co/storage/v1/object/authenticated/proposal-letters/doc{index}.pdf",
            submitted_by=users["treasurer"].id))
    db.commit()
    signed = []
    monkeypatch.setattr("app.routers.files.signed_file_url", lambda url, bucket: signed.append(url) or "https://signed.example/link")
    login("signatory")
    own, foreign = db.query(EventProposalLetter).order_by(EventProposalLetter.title).all()
    assert client.get("/proposal-letters").json()[0]["id"] == str(own.id)
    assert len(client.get("/proposal-letters").json()) == 1
    assert client.get(f"/proposal-letters/{foreign.id}").status_code == 403
    assert client.get(f"/events/{resources[1]['events'].id}").status_code == 403
    assert client.get("/files", params={"reference": own.document_url}).status_code == 200
    assert client.get("/files", params={"reference": foreign.document_url}).status_code == 404
    assert len(signed) == 1
    assert client.get("/auth/me").json()["role"] == "signatory"
    assert client.get("/auth/permissions").json()["role"] == "signatory"
    assert client.get("/notifications").status_code == 200
    resources[0]["events"].status = "pending_admin"
    db.commit()
    assert client.get(path).status_code == 403
    assert client.get("/proposal-letters").json() == []
    assert client.get("/files", params={"reference": own.document_url}).status_code == 404


def test_super_admin_provisions_signatory_and_suspends_access(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    sent = []
    monkeypatch.setattr("app.services.account_provisioning.send_otp_email", lambda *a, **k: sent.append((a, k)))
    payload = {"full_name": "Institution reviewer", "email": "reviewer@example.com", "position": "VPAA"}
    login("admin")
    assert client.post("/auth/register/signatory", json=payload).status_code == 403
    assert client.patch(f"/users/{users['officer'].id}/access", json={"role": "signatory"}).status_code == 403
    login("super_admin")
    created = client.post("/auth/register/signatory", json=payload)
    assert created.status_code == 201, created.text
    assert created.json()["role"] == "signatory"
    assert created.json()["organization_id"] is None
    assert created.json()["must_change_password"] is True
    assert len(sent) == 1
    token = login("signatory")
    login("super_admin")
    assert client.patch(f"/users/{users['signatory'].id}/access", json={"is_suspended": True}).status_code == 200
    client.headers["Authorization"] = "Bearer " + token
    assert client.get("/events").status_code == 401


def test_signatory_real_login_and_account_role_change(system):
    client, db, users, orgs, resources, login = system
    users["signatory"].password_hash = hash_password("test-password-123")
    db.commit()
    result = client.post("/auth/login", data={"username": users["signatory"].email, "password": "test-password-123"})
    assert result.status_code == 200, result.text
    login("super_admin")
    result = client.patch(f"/users/{users['sds_staff'].id}/access", json={"role": "signatory"})
    assert result.status_code == 200, result.text
    assert result.json()["department_id"] is None
    picker = client.get("/users/signatories").json()
    assert len(picker) == 2
    assert all(set(row) == {"id", "full_name", "position"} for row in picker)


def test_compliance_schema_defaults_and_cross_event_constraints(system):
    client, db, users, orgs, resources, login = system
    event_ids = [resource["events"].id for resource in resources]
    participants = [EventParticipant(event_id=event_id, student_number="2026-001", full_name="Test Student") for event_id in event_ids]
    requirements = [EventRequirement(event_id=event_id, name="Consent", phase="pre_activity") for event_id in event_ids]
    db.add_all(participants + requirements)
    db.commit()
    record = StudentComplianceRecord(event_id=event_ids[0], participant_id=participants[0].id, requirement_id=requirements[0].id)
    db.add(record)
    db.commit()
    assert record.status == "MISSING"
    for participant, requirement in [(participants[1], requirements[0]), (participants[0], requirements[1])]:
        with pytest.raises(IntegrityError), db.begin_nested():
            db.add(StudentComplianceRecord(event_id=event_ids[0], participant_id=participant.id, requirement_id=requirement.id))
            db.flush()
    for invalid in ["CLEARED", "verified", "unknown"]:
        with pytest.raises(IntegrityError), db.begin_nested():
            record.status = invalid
            db.flush()
    with pytest.raises(IntegrityError), db.begin_nested():
        record.status = "VERIFIED"
        db.flush()
    record.reviewed_by = users["adviser"].id
    record.reviewed_at = datetime.now(timezone.utc)
    record.status = "VERIFIED"
    db.commit()
    assert record.status == "VERIFIED"
    with pytest.raises(IntegrityError), db.begin_nested():
        db.add(EventParticipant(event_id=event_ids[0], student_number="2026-001", full_name="Duplicate"))
        db.flush()


def test_requirement_presets_can_be_read_without_exposing_compliance_data(system):
    client, db, users, orgs, resources, login = system
    db.add(RequirementPreset(code="medical_clearance", name="Medical Clearance", phase="pre_activity", is_sensitive=True))
    db.commit()
    login("adviser")
    result = client.get("/events/requirement-presets")
    assert result.status_code == 200, result.text
    assert result.json()[0]["is_sensitive"] is True


def test_draft_deletion_removes_unused_routing(system):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    result = client.post("/events", json={"title": "Unused draft", "school_year": "2026-2027",
        "semester": "1st", "event_scope": "organizational"})
    assert result.status_code == 201
    path = f"/events/{result.json()['id']}"
    login("admin")
    assert client.put(path + "/routing", json={"signatory_ids": [str(users["signatory"].id)]}).status_code == 200
    assert client.delete(path).status_code == 204
    assert db.query(DocumentRouting).count() == 0
