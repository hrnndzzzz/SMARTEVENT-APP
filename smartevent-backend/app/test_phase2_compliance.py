"""Staff-only Phase 2 API behavior, authorization and approval gates."""
from datetime import date
from uuid import UUID, uuid4

import pytest

from app.models import Approval, AuditLog, DocumentRouting, EventParticipant, RequirementPreset, StudentComplianceRecord
from app.models_compliance import EventComplianceDocument, EventLogistics
from app.test_access_management import system


@pytest.fixture
def phase2(system, monkeypatch):
    from app.config import settings
    monkeypatch.setattr(settings, "supabase_url", "https://test.supabase.co")
    client, db, users, orgs, resources, login = system
    event = resources[0]["events"]
    event.status = "draft"
    event.event_date = date(2026, 12, 1)
    db.add_all([
        RequirementPreset(code="parent_guardian_consent", name="Consent", phase="pre_activity", requires_notarization=True),
        RequirementPreset(code="medical_clearance", name="Medical", phase="pre_activity", is_sensitive=True),
    ])
    db.commit()
    monkeypatch.setattr("app.services.compliance.upload_proposal_letter", lambda *args: f"https://test.supabase.co/storage/v1/object/authenticated/proposal-letters/{uuid4()}.pdf")
    monkeypatch.setattr("app.services.compliance.signed_file_url", lambda *args: "https://test.supabase.co/storage/v1/object/sign/proposal-letters/test.pdf?token=test")
    login("admin")
    return system, f"/events/{event.id}"


def off_campus(phase2, count=1, mode="none"):
    system, path = phase2
    client = system[0]
    result = client.put(path + "/logistics", json={"activity_location": "off_campus", "destination": "Museum",
        "transport_mode": mode, "transport_notes": "Walking to adjacent museum" if mode == "none" else None})
    assert result.status_code == 200, result.text
    result = client.post(path + "/participants", json=[{"student_number": f"S{i}", "full_name": f"Student {i}"} for i in range(count)])
    assert result.status_code == 201, result.text
    return client.get(path + "/compliance").json()


def review_students(client, path, **overrides):
    records = client.get(path + "/compliance").json()["records"]
    result = None
    for offset in range(0, len(records), 100):
        result = client.post(path + "/compliance/batch-review", json={
            "records": [{"id": row["id"], "version": row["version"]} for row in records[offset:offset + 100]],
            "decision": "VERIFIED", "evidence_mode": "physical", "notarization_confirmed": True,
            "remarks": "Originals checked and held in departmental file A", **overrides})
    return result


def pic(client, path, reference="EMP1"):
    return client.post(path + "/personnel", json={"staff_reference": reference, "full_name": "Faculty PIC",
        "position": "Faculty", "qualifications": "Experienced field trip supervisor", "institution_employee_confirmed": True})


def evidence(client, path, kind, vehicle=None, expiry=None):
    data = {"kind": kind, "reference_number": "Evidence 123"}
    if vehicle:
        data["vehicle_id"] = vehicle
    if expiry:
        data["valid_until"] = expiry
    uploaded = client.post(path + "/compliance-documents", data=data,
        files={"file": ("proof.pdf", b"%PDF-1.7\nTest document\n%%EOF", "application/pdf")})
    assert uploaded.status_code == 201, uploaded.text
    document = uploaded.json()
    result = client.post(path + f"/compliance-documents/{document['id']}/review", json={
        "version": document["version"], "decision": "VERIFIED", "validity_confirmed": True, "remarks": "Checked original and activity date"})
    return result


@pytest.mark.parametrize("role", ["adviser", "treasurer", "officer", "sds_staff", "signatory"])
def test_only_admin_manages_roster(phase2, role):
    system, path = phase2
    client, db, users, orgs, resources, login = system
    login(role)
    assert client.post(path + "/participants", json=[{"student_number": "S1", "full_name": "Student"}]).status_code == 403
    assert db.query(EventParticipant).count() == 0


@pytest.mark.parametrize("role", ["treasurer", "officer", "sds_staff", "signatory"])
def test_private_student_records_are_staff_only(phase2, role):
    system, path = phase2
    client, db, users, orgs, resources, login = system
    record = off_campus(phase2)["records"][0]
    login(role)
    assert client.get(path + "/compliance").status_code == 403
    assert client.get(path + f"/compliance/{record['id']}/file").status_code == 403
    assert client.post(path + "/compliance/batch-review", json={}).status_code == 403


def test_staff_batch_physical_verification_and_notarization(phase2):
    system, path = phase2
    client, db, users, orgs, resources, login = system
    off_campus(phase2, count=2)
    login("adviser")
    assert review_students(client, path, notarization_confirmed=False).status_code == 422
    assert all(row.status == "MISSING" for row in db.query(StudentComplianceRecord))
    reviewed = review_students(client, path)
    assert reviewed.status_code == 200, reviewed.text
    assert all(row["evidence_mode"] == "physical" and not row["has_document"] and row["version"] == 2 for row in reviewed.json())
    assert all(row.reviewed_by == users["adviser"].id for row in db.query(StudentComplianceRecord))
    assert db.query(AuditLog).filter_by(action="compliance.student_documents_reviewed").count() == 1
    assert len(users) == 7  # Roster records never provision accounts.


def test_digital_review_requires_file_and_versions_are_atomic(phase2):
    system, path = phase2
    client, db, users, orgs, resources, login = system
    records = off_campus(phase2)["records"]
    assert review_students(client, path, evidence_mode="digital").status_code == 409
    result = client.post(path + "/compliance/batch-review", json={"records": [
        {"id": records[0]["id"], "version": 1}, {"id": records[1]["id"], "version": 99}],
        "decision": "VERIFIED", "evidence_mode": "physical", "notarization_confirmed": True, "remarks": "Checked"})
    assert result.status_code == 409
    assert all(row.status == "MISSING" for row in db.query(StudentComplianceRecord))
    assert review_students(client, path, remarks=" ").status_code == 422


def test_upload_resets_verification_and_private_links_are_authorized(phase2):
    system, path = phase2
    client, db, users, orgs, resources, login = system
    records = off_campus(phase2)["records"]
    assert review_students(client, path).status_code == 200
    endpoint = path + f"/compliance/{records[0]['id']}"
    assert client.get(endpoint + "/file").status_code == 404
    for content, mime in [(b"bad", "application/pdf"), (b"x", "text/html"), (b"fake", "image/png")]:
        assert client.post(endpoint + "/upload", data={"version": 2}, files={"file": ("bad", content, mime)}).status_code == 400
    upload = client.post(endpoint + "/upload", data={"version": 2}, files={"file": ("good.pdf", b"%PDF-1.7\n%%EOF", "application/pdf")})
    assert upload.status_code == 200, upload.text
    assert upload.json()["status"] == "SUBMITTED" and upload.json()["version"] == 3
    assert upload.json()["reviewed_by"] is None and not upload.json()["notarization_confirmed"]
    assert "document_url" not in upload.json()
    assert client.get(endpoint + "/file").json()["expires_in"] == 300
    assert client.post(endpoint + "/upload", data={"version": 2}, files={"file": ("good.pdf", b"%PDF-1.7\n%%EOF", "application/pdf")}).status_code == 409
    foreign = f"/events/{resources[1]['events'].id}/compliance/{records[0]['id']}/file"
    assert client.get(foreign).status_code == 404
    assert client.get("/files", params={"reference": db.get(StudentComplianceRecord, UUID(records[0]["id"])).document_url}).status_code == 404


@pytest.mark.parametrize("count,expected", [(50, True), (51, False)])
def test_ratio_boundary_lgu_requirements_and_readiness(phase2, count, expected):
    system, path = phase2
    client = system[0]
    off_campus(phase2, count=count)
    assert pic(client, path).status_code == 201
    assert review_students(client, path).status_code == 200
    assert not client.get(path + "/readiness").json()["ready"]
    for kind in ["lgu_coordination", "agency_acknowledgment"]:
        assert evidence(client, path, kind).status_code == 200
    result = client.get(path + "/readiness").json()
    assert result["ready"] is expected
    assert result["required_pic_count"] == (1 if expected else 2)
    if not expected:
        assert pic(client, path, "EMP2").status_code == 201
        assert client.get(path + "/readiness").json()["ready"]


def test_no_pic_and_zero_roster_block_off_campus_but_not_on_campus(phase2):
    system, path = phase2
    client = system[0]
    assert client.get(path + "/readiness").json()["ready"]
    assert client.put(path + "/logistics", json={"activity_location": "off_campus", "destination": "Museum", "transport_mode": "none"}).status_code == 200
    blockers = client.get(path + "/readiness").json()["blockers"]
    assert any("at least one" in row for row in blockers)
    assert any("PIC" in row for row in blockers)
    assert any("Explain" in row for row in blockers)


def test_third_party_requires_all_vehicle_evidence_and_special_permit(phase2):
    system, path = phase2
    client = system[0]
    off_campus(phase2, mode="third_party")
    vehicle = client.post(path + "/vehicles", json={"plate_number": "ABC-123", "operator_name": "Carrier", "driver_name": "Driver", "out_of_line": True})
    assert vehicle.status_code == 201
    assert vehicle.json()["plate_number"] == "ABC123"
    vehicle_id = vehicle.json()["id"]
    assert evidence(client, path, "insurance", vehicle_id, "2026-01-01").status_code == 422
    for kind in ["vehicle_registration", "driver_license", "roadworthiness", "ltfrb_franchise", "dot_accreditation"]:
        assert evidence(client, path, kind, vehicle_id, "2027-01-01").status_code == 200
    blockers = client.get(path + "/readiness").json()["blockers"]
    assert any("special permit" in row for row in blockers)
    assert any("insurance" in row for row in blockers)
    assert not any("roadworthiness" in row for row in blockers)
    assert client.post(path + "/vehicles", json={"plate_number": "---", "operator_name": "Carrier", "driver_name": "Driver"}).status_code == 422


def test_unknown_classification_blocks_admin_and_final_without_decision(phase2):
    system, path = phase2
    client, db, users, orgs, resources, login = system
    event = resources[0]["events"]
    db.delete(db.get(EventLogistics, event.id))
    event.status = "pending_admin"
    db.commit()
    assert client.put(path + "/routing", json={"signatory_ids": [str(users["signatory"].id)]}).status_code == 200
    assert client.post(path + "/approve", json={}).status_code == 409
    assert db.query(Approval).count() == 0
    event.status = "pending_institutional_review"
    db.commit()
    login("signatory")
    assert client.post(path + "/approve", json={}).status_code == 409
    assert db.query(DocumentRouting).one().status == "pending"
    assert db.query(Approval).count() == 0


@pytest.mark.parametrize("status", ["pending_institutional_review", "approved", "completed"])
def test_evidence_and_roster_frozen_after_handoff(phase2, status):
    system, path = phase2
    client, db, users, orgs, resources, login = system
    off_campus(phase2)
    resources[0]["events"].status = status
    db.commit()
    assert review_students(client, path).status_code == 409
    assert client.post(path + "/participants", json=[{"student_number": "S2", "full_name": "Student 2"}]).status_code == 409


def test_withdrawal_retains_paper_trail_and_verified_identity_cannot_change(phase2):
    system, path = phase2
    client, db, users, orgs, resources, login = system
    participant = off_campus(phase2)["participants"][0]
    assert review_students(client, path).status_code == 200
    endpoint = path + f"/participants/{participant['id']}"
    assert client.patch(endpoint, json={"full_name": "Other student", "is_active": True}).status_code == 409
    assert client.patch(endpoint, json={"full_name": participant["full_name"], "is_active": False}).status_code == 200
    assert db.query(StudentComplianceRecord).count() == 2
    assert client.get(path + "/readiness").json()["participant_count"] == 0
    assert client.patch(endpoint, json={"full_name": participant["full_name"], "is_active": True}).status_code == 200
    assert db.query(StudentComplianceRecord).count() == 2


def test_required_defaults_cannot_be_disabled_and_pic_must_be_employee(phase2):
    system, path = phase2
    client = system[0]
    bundle = off_campus(phase2)
    for row in bundle["requirements"]:
        assert client.patch(path + f"/requirements/{row['id']}", json={"is_required": False}).status_code == 409
    assert client.post(path + "/personnel", json={"staff_reference": "S1", "full_name": "Student", "position": "Volunteer",
        "qualifications": "None", "institution_employee_confirmed": False}).status_code == 422


def test_date_and_destination_changes_require_fresh_verification(phase2):
    system, path = phase2
    client, db, users, orgs, resources, login = system
    off_campus(phase2)
    assert review_students(client, path).status_code == 200
    assert evidence(client, path, "lgu_coordination").status_code == 200
    assert client.patch(path, json={"event_date": "2026-12-02"}).status_code == 200
    assert all(row.status == "MISSING" and row.version == 3 for row in db.query(StudentComplianceRecord))
    document = db.query(EventComplianceDocument).one()
    assert document.status == "SUBMITTED" and document.reviewed_by is None
    assert review_students(client, path).status_code == 200
    assert client.put(path + "/logistics", json={"activity_location": "off_campus", "destination": "Different museum", "transport_mode": "none", "transport_notes": "Walk"}).status_code == 200
    assert all(row.status == "MISSING" and not row.notarization_confirmed for row in db.query(StudentComplianceRecord))


def test_no_separate_workspace_or_student_portal(system):
    client = system[0]
    page = client.get("/compliance-workspace")
    assert page.status_code == 404
    assert client.get("/compliance-workspace/workspace.js").status_code == 404
    assert client.get("/student-portal").status_code == 404


def test_signatory_reads_assigned_logistics_not_student_records(phase2):
    system, path = phase2
    client, db, users, orgs, resources, login = system
    assert evidence(client, path, "lgu_coordination").status_code == 200
    document = db.query(EventComplianceDocument).one()
    assert client.put(path + "/routing", json={"signatory_ids": [str(users["signatory"].id)]}).status_code == 200
    resources[0]["events"].status = "pending_institutional_review"
    db.commit()
    login("signatory")
    assert client.get(path + "/logistics").status_code == 200
    assert client.get(path + "/readiness").status_code == 200
    assert client.get(path + f"/compliance-documents/{document.id}/file").status_code == 200
    assert client.get(path + "/compliance").status_code == 403
    assert client.get(f"/events/{resources[1]['events'].id}/logistics").status_code == 403
    assert client.post(path + f"/compliance-documents/{document.id}/review", json={}).status_code == 403


def test_duplicate_roster_and_pic_do_not_inflate_counts(phase2):
    system, path = phase2
    client, db, *_ = system
    off_campus(phase2)
    assert client.post(path + "/participants", json=[{"student_number": "s0", "full_name": "Duplicate"}]).status_code == 409
    db.rollback()
    assert pic(client, path).status_code == 201
    assert pic(client, path, "emp1").status_code == 409
    db.rollback()
    result = client.get(path + "/readiness").json()
    assert result["participant_count"] == 1 and result["pic_count"] == 1


def test_complete_off_campus_workflow_and_retained_paper_trail(phase2):
    system, path = phase2
    client, db, users, orgs, resources, login = system
    off_campus(phase2)
    assert pic(client, path).status_code == 201
    assert review_students(client, path).status_code == 200
    for kind in ["lgu_coordination", "agency_acknowledgment"]:
        assert evidence(client, path, kind).status_code == 200
    assert client.delete(path).status_code == 409
    assert client.put(path + "/routing", json={"signatory_ids": [str(users["signatory"].id)]}).status_code == 200
    login("treasurer")
    assert client.post(path + "/submit").status_code == 200
    login("adviser")
    assert client.post(path + "/approve", json={}).status_code == 200
    login("admin")
    assert client.post(path + "/approve", json={}).status_code == 200
    login("signatory")
    final = client.post(path + "/approve", json={})
    assert final.status_code == 200, final.text
    assert final.json()["status"] == "approved"
    assert db.query(StudentComplianceRecord).count() == 2
