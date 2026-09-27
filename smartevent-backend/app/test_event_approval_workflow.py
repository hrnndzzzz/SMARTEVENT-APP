"""Regression coverage for the rebased two-stage event approval workflow."""

import pytest

from app.models import Approval
from app.test_access_management import system


@pytest.mark.parametrize("legacy_status", ["pending", "pending_adviser"])
def test_two_stage_approval_and_history(system, legacy_status):
    client, db, users, orgs, resources, login = system
    event = resources[0]["events"]
    event.status = legacy_status
    db.commit()
    endpoint = f"/events/{event.id}"
    login("admin")
    assert client.post(endpoint + "/approve", json={}).status_code == 409
    login("adviser")
    first = client.post(endpoint + "/approve", json={"remarks": "Adviser review"})
    assert first.status_code == 200, first.text
    assert first.json()["status"] == "pending_admin"
    assert client.post(endpoint + "/approve", json={}).status_code == 409
    login("admin")
    final = client.post(endpoint + "/approve", json={"remarks": "Final review"})
    assert final.status_code == 200, final.text
    assert final.json()["status"] == "approved"
    history = client.get(endpoint + "/approvals").json()
    assert [row["step_order"] for row in history] == [1, 2]
    assert [row["reviewer_id"] for row in history] == [str(users["adviser"].id), str(users["admin"].id)]


@pytest.mark.parametrize("role,expected", [
    ("treasurer", "pending_adviser"), ("adviser", "pending_admin"),
    ("admin", "pending_adviser"), ("super_admin", "pending_adviser"),
])
def test_creation_never_auto_approves_and_blocks_self_review(system, role, expected):
    client, db, users, orgs, resources, login = system
    login(role)
    result = client.post("/events", json={
        "title": "Proposal", "school_year": "2026-2027", "semester": "1st",
        "event_scope": "organizational", "organization_id": str(orgs[0].id),
        "department_id": str(orgs[0].department_id), "status": "pending",
    })
    assert result.status_code == 201, result.text
    assert result.json()["status"] == expected
    if role != "treasurer":
        for action in ("approve", "reject"):
            assert client.post(f"/events/{result.json()['id']}/{action}", json={}).status_code == 403


def test_admin_resubmission_preserves_original_review_chain_and_history(system):
    client, db, users, orgs, resources, login = system
    event = resources[0]["events"]
    endpoint = f"/events/{event.id}"
    login("adviser")
    assert client.post(endpoint + "/reject", json={}).status_code == 200
    login("admin")
    assert client.patch(endpoint, json={"title": "Revised"}).status_code == 200
    response = client.post(endpoint + "/submit")
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "pending_adviser"
    history = client.get(endpoint + "/approvals").json()
    assert [row["decision"] for row in history] == ["rejected", "resubmitted"]
    assert client.post(endpoint + "/approve", json={}).status_code == 409


@pytest.mark.parametrize("role", ["adviser", "admin", "super_admin"])
def test_missing_academic_metadata_blocks_both_review_stages(system, role):
    client, db, users, orgs, resources, login = system
    event = resources[0]["events"]
    event.status = "pending_adviser" if role == "adviser" else "pending_admin"
    event.school_year = None
    db.commit()
    login(role)
    assert client.post(f"/events/{event.id}/approve", json={}).status_code == 409
    assert db.query(Approval).count() == 0


@pytest.mark.parametrize("role", ["adviser", "admin"])
@pytest.mark.parametrize("action", ["approve", "reject"])
def test_cross_organization_review_remains_blocked(system, role, action):
    client, db, users, orgs, resources, login = system
    event = resources[1]["events"]
    event.status = "pending_adviser" if role == "adviser" else "pending_admin"
    db.commit()
    login(role)
    assert client.post(f"/events/{event.id}/{action}", json={}).status_code == 403
