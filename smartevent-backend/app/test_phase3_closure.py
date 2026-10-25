from datetime import timedelta
from uuid import UUID

import pytest

from app.models import Approval, EventParticipant, EventRequirement, RequirementPreset, StudentComplianceRecord
from app.models_compliance import EventParallelActivity
from app.services.closure import institution_today
from app.test_access_management import system
from app.test_phase2_compliance import phase2, off_campus


@pytest.fixture
def closure(phase2):
    state, path = phase2
    client, db, users, orgs, resources, login = state
    db.add(RequirementPreset(code="student_learning_journal", name="Learning journal", phase="post_activity"))
    db.commit()
    off_campus(phase2, count=2)
    event = resources[0]["events"]
    event.event_date = institution_today() - timedelta(days=1)
    event.status = "approved"
    db.commit()
    return phase2


def complete(closure):
    state, path = closure
    return state[0].post(path + "/complete", json={"completed_on": str(institution_today()), "remarks": "Activity concluded; originals retained by the department"})


def report(closure, kind):
    state, path = closure
    return state[0].post(path + "/post-activity/documents", data={"kind": kind, "reference_number": "FILE-001"},
        files={"file": ("proof.pdf", b"%PDF-1.7\n%%EOF", "application/pdf")})


def assignment(closure, participant_id, version=0):
    state, path = closure
    return state[0].post(path + "/parallel-activities", json={"participant_id": str(participant_id), "title": "Museum research project",
        "learning_objectives": "Explain the same historical learning outcomes", "instructions": "Research and submit a reflection",
        "reason": "Unable to attend; equivalent alternative provided", "version": version})


@pytest.mark.parametrize("role", ["treasurer", "officer", "sds_staff", "signatory"])
def test_attendance_and_closure_are_staff_only(closure, role):
    state, path = closure
    client, db, users, orgs, resources, login = state
    login(role)
    assert client.get(path + "/attendance.pdf").status_code == 403
    assert client.get(path + "/post-activity").status_code == 403
    assert complete(closure).status_code == 403
    assert client.post(path + "/parallel-activities", json={}).status_code == 403


def test_attendance_pdf_filters_roster_and_has_no_attendance_side_effect(closure, monkeypatch):
    state, path = closure
    client, db, users, orgs, resources, login = state
    participants = db.query(EventParticipant).order_by(EventParticipant.student_number).all()
    participants[0].is_active = False
    db.commit()
    observed = []
    monkeypatch.setattr("app.routers.closure.render_attendance", lambda event, organization, destination, rows:
        observed.extend(rows) or b"%PDF-demo")
    before = db.query(Approval).count()
    result = client.get(path + "/attendance.pdf")
    assert result.status_code == 200 and result.headers["content-type"] == "application/pdf"
    assert result.headers["cache-control"] == "no-store"
    assert observed == [participants[1]]
    assert db.query(Approval).count() == before and resources[0]["events"].status == "approved"
    login("adviser")
    assert client.get(path + "/attendance.pdf").status_code == 200
    assert client.get(f"/events/{resources[1]['events'].id}/attendance.pdf").status_code == 403


@pytest.mark.parametrize("status", ["draft", "pending_admin", "rejected", "pending_institutional_review"])
def test_printing_requires_approved_or_completed_event(closure, status):
    state, path = closure
    state[4][0]["events"].status = status
    state[1].commit()
    assert state[0].get(path + "/attendance.pdf").status_code == 409
    assert complete(closure).status_code == 409


def test_real_pdf_generation_and_empty_roster(closure):
    state, path = closure
    client, db, *_ = state
    response = client.get(path + "/attendance.pdf")
    assert response.status_code == 200 and response.content.startswith(b"%PDF-")
    for participant in db.query(EventParticipant):
        participant.is_active = False
    db.commit()
    assert client.get(path + "/attendance.pdf").status_code == 409


def test_parallel_students_are_not_printed_and_closure_files_are_private(closure, monkeypatch):
    state, path = closure
    client, db, users, orgs, resources, login = state
    participants = db.query(EventParticipant).order_by(EventParticipant.student_number).all()
    resources[0]["events"].status = "draft"
    db.commit()
    assert assignment(closure, participants[0].id).status_code == 201
    resources[0]["events"].status = "approved"
    db.commit()
    observed = []
    monkeypatch.setattr("app.routers.closure.render_attendance", lambda event, organization, destination, rows:
        observed.extend(rows) or b"%PDF-demo")
    assert client.get(path + "/attendance.pdf").status_code == 200
    assert observed == [participants[1]]
    uploaded = report(closure, "signed_attendance")
    assert uploaded.status_code == 201
    document_path = path + "/compliance-documents/" + uploaded.json()["id"] + "/file"
    assert client.get(document_path).status_code == 200
    login("treasurer")
    assert client.get(document_path).status_code == 403
    assert not client.get(path + "/logistics").json()["documents"]


def test_completion_unlocks_journals_and_retains_approvals(closure):
    state, path = closure
    client, db, users, orgs, resources, login = state
    before = db.query(Approval).count()
    result = complete(closure)
    assert result.status_code == 200, result.text
    assert result.json()["status"] == "completed" and result.json()["completed_by"] == str(users["admin"].id)
    assert db.query(Approval).count() == before
    requirements = db.query(EventRequirement).filter_by(phase="post_activity").all()
    assert len(requirements) == 1
    assert db.query(StudentComplianceRecord).filter_by(requirement_id=requirements[0].id).count() == 2
    assert complete(closure).status_code == 409
    assert client.post(path + "/post-activity/initialize").status_code == 200
    assert db.query(EventRequirement).filter_by(phase="post_activity").count() == 1
    assert client.get(path + "/post-activity").json()["readiness"]["status"] == "OPEN"


def test_legacy_custom_requirements_do_not_replace_the_required_journal(closure):
    state, path = closure
    client, db, *_ = state
    assert complete(closure).status_code == 200
    journal = db.query(EventRequirement).filter_by(phase="post_activity").one()
    journal.is_required = False
    db.add(EventRequirement(event_id=journal.event_id, phase="post_activity", name="Custom feedback", is_required=True))
    db.commit()
    blockers = client.get(path + "/post-activity").json()["readiness"]["blockers"]
    assert "Initialize the post-activity learning-journal requirement" in blockers
    assert client.post(path + "/post-activity/initialize").status_code == 200
    db.refresh(journal)
    assert journal.is_required
    assert "Initialize the post-activity learning-journal requirement" not in client.get(path + "/post-activity").json()["readiness"]["blockers"]


@pytest.mark.parametrize("delta", [-2, 1])
def test_completion_dates_are_validated(closure, delta):
    state, path = closure
    result = state[0].post(path + "/complete", json={"completed_on": str(institution_today() + timedelta(days=delta)), "remarks": "Test"})
    assert result.status_code == 422
    assert state[4][0]["events"].status == "approved"


def test_signed_attendance_before_completion_and_stale_review(closure):
    state, path = closure
    client = state[0]
    uploaded = report(closure, "signed_attendance")
    assert uploaded.status_code == 201, uploaded.text
    document = uploaded.json()
    assert "document_url" not in document
    assert report(closure, "debriefing_report").status_code == 409
    endpoint = path + f"/post-activity/documents/{document['id']}/review"
    review = {"version": document["version"], "decision": "VERIFIED", "remarks": "Original signatures checked"}
    assert client.post(endpoint, json={**review, "version": 999}).status_code == 409
    assert client.post(endpoint, json=review).status_code == 200
    assert client.post(endpoint, json=review).status_code == 409


def test_post_activity_physical_and_digital_reviews_and_closeout(closure):
    state, path = closure
    client, db, *_ = state
    assert complete(closure).status_code == 200
    bundle = client.get(path + "/compliance").json()
    requirement_ids = {row["id"] for row in bundle["requirements"] if row["phase"] == "post_activity"}
    records = [row for row in bundle["records"] if row["requirement_id"] in requirement_ids]
    review = {"records": [{"id": row["id"], "version": row["version"]} for row in records],
        "decision": "VERIFIED", "evidence_mode": "physical", "remarks": "Original journals checked"}
    assert client.post(path + "/compliance/batch-review", json=review).status_code == 409
    assert client.post(path + "/post-activity/compliance/batch-review", json={**review, "evidence_mode": "digital"}).status_code == 409
    assert client.post(path + "/post-activity/compliance/batch-review", json=review).status_code == 200
    assert client.get(path + "/post-activity").json()["readiness"]["unverified_document_count"] == 0
    for kind in ["signed_attendance", "debriefing_report", "final_expense_report"]:
        document = report(closure, kind).json()
        assert client.post(path + f"/post-activity/documents/{document['id']}/review", json={"version": document["version"], "decision": "VERIFIED", "remarks": "Reviewed departmental original"}).status_code == 200
    assert client.get(path + "/post-activity").json()["readiness"]["status"] == "CLOSED"
    record = records[0]
    assert client.post(path + f"/post-activity/compliance/{record['id']}/upload", data={"version": 2},
        files={"file": ("journal.pdf", b"%PDF-1.7\n%%EOF", "application/pdf")}).status_code == 200
    assert client.get(path + "/post-activity").json()["readiness"]["status"] == "OPEN"


def test_parallel_assignment_excludes_travel_and_requires_equivalent_work(closure):
    state, path = closure
    client, db, users, orgs, resources, login = state
    participant = db.query(EventParticipant).order_by(EventParticipant.student_number).first()
    assert assignment(closure, participant.id).status_code == 409  # Institutional/approved roster is frozen.
    resources[0]["events"].status = "draft"
    db.commit()
    assigned = assignment(closure, participant.id)
    assert assigned.status_code == 201, assigned.text
    activity = assigned.json()
    assert client.get(path + "/readiness").json()["participant_count"] == 1
    assert assignment(closure, participant.id).status_code == 409
    resources[0]["events"].status = "approved"
    db.commit()
    assert complete(closure).status_code == 200
    requirement = db.query(EventRequirement).filter_by(phase="post_activity").one()
    assert db.query(StudentComplianceRecord).filter_by(requirement_id=requirement.id).count() == 1
    assert client.get(path + "/post-activity").json()["readiness"]["unverified_parallel_count"] == 1
    review = {"records": [{"id": activity["id"], "version": activity["version"]}], "decision": "VERIFIED", "evidence_mode": "physical", "remarks": "Equivalent learning outcomes demonstrated"}
    assert client.post(path + f"/parallel-activities/{activity['id']}/review", json=review).status_code == 200
    assert client.get(path + "/post-activity").json()["readiness"]["unverified_parallel_count"] == 0
    assert client.patch(path + f"/participants/{participant.id}/participation", json={"participation_mode": "attending", "remarks": "Corrected actual attendance"}).status_code == 200
    assert not db.get(EventParallelActivity, UUID(activity["id"])).is_active
    assert db.query(StudentComplianceRecord).filter_by(requirement_id=requirement.id).count() == 2


def test_parallel_scope_and_file_privacy(closure):
    state, path = closure
    client, db, users, orgs, resources, login = state
    resources[0]["events"].status = "completed"
    db.commit()
    student = db.query(EventParticipant).first()
    activity = assignment(closure, student.id).json()
    login("treasurer")
    assert client.get(path + f"/parallel-activities/{activity['id']}/file").status_code == 403
    login("admin")
    assert client.get(path + f"/parallel-activities/{activity['id']}/file").status_code == 404
    endpoint = path + f"/parallel-activities/{activity['id']}/upload"
    assert client.post(endpoint, data={"version": activity["version"]}, files={"file": ("work.pdf", b"%PDF-1.7\n%%EOF", "application/pdf")}).status_code == 200
    assert client.get(path + f"/parallel-activities/{activity['id']}/file").json()["expires_in"] == 300
    assert client.get(f"/events/{resources[1]['events'].id}/parallel-activities/{activity['id']}/file").status_code == 404


def test_no_qr_boarding_routes_exist(system):
    from app.main import app
    assert not any('boarding' in route or '/qr' in route for route in app.openapi()['paths'])
