"""Core workflows use isolated records and mocked email, never the live database."""
from datetime import datetime, timedelta, timezone
from uuid import uuid4
import pytest
from app.test_access_management import system
from app.models import AuditLog, CiteMember, Notification, OtpToken, User
from app.security import create_access_token
from app.services.otp import hash_otp_code
from app.services.notifications import deliver_notification
from app.services.report_exports import render_export


def pending_registration(system):
    client, db, users, orgs, resources, login = system
    user = User(full_name="New Officer", email="new@example.com", role="officer",
                password_hash="unused", is_active=False, must_change_password=False,
                department_id=orgs[0].department_id, organization_id=orgs[0].id)
    db.add(user)
    db.flush()
    member = CiteMember(full_name=user.full_name, email=user.email, role=user.role,
                        department_id=user.department_id, organization_id=user.organization_id,
                        claimed_by_user_id=user.id)
    token = OtpToken(user_id=user.id, purpose="registration", code_hash=hash_otp_code("123456"),
                     expires_at=datetime.now(timezone.utc) + timedelta(minutes=10))
    db.add_all([member, token])
    db.commit()
    return user, member, token


def verify(client, user, code="123456"):
    return client.post("/auth/verify-otp", json={"email": user.email, "otp_code": code})


def test_registration_auto_approval_and_single_confirmation(system, monkeypatch):
    client, db, *_ = system
    user, member, token = pending_registration(system)
    sent = []
    monkeypatch.setattr("app.services.notifications.send_email", lambda *a, **k: sent.append((a, k)))
    response = verify(client, user)
    assert response.status_code == 200, response.text
    assert response.json()["registration_status"] == "approved"
    assert response.json()["confirmation_email_status"] == "sent"
    assert user.is_active and token.used_at
    assert db.query(Notification).count() == 1
    assert db.query(AuditLog).filter(AuditLog.action == "user.registration_approved").count() == 1
    assert len(sent) == 1 and sent[0][1]["idempotency_key"].startswith("registration-confirmation/")
    assert verify(client, user).status_code == 200
    assert len(sent) == 1 and db.query(Notification).count() == 1


def test_confirmation_delivery_failure_is_retryable_without_revoking_approval(system, monkeypatch):
    client, db, *_ = system
    user, member, token = pending_registration(system)
    def fail(*a, **k):
        raise RuntimeError("provider unavailable")
    monkeypatch.setattr("app.services.notifications.send_email", fail)
    response = verify(client, user)
    assert response.status_code == 200 and user.is_active
    assert response.json()["confirmation_email_status"] == "failed"
    notification = db.query(Notification).one()
    assert notification.email_attempts == 1
    sent = []
    monkeypatch.setattr("app.services.notifications.send_email", lambda *a, **k: sent.append(a))
    deliver_notification(db, notification.id)
    deliver_notification(db, notification.id)
    assert notification.email_status == "sent" and notification.email_attempts == 2
    assert len(sent) == 1


@pytest.mark.parametrize("problem", ["wrong_code", "expired", "removed", "role", "organization", "suspended"])
def test_registration_invalid_requirements_never_activate_or_notify(system, monkeypatch, problem):
    client, db, users, orgs, resources, login = system
    user, member, token = pending_registration(system)
    if problem == "expired":
        token.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    elif problem == "removed":
        db.delete(member)
    elif problem == "role":
        member.role = "admin"
    elif problem == "organization":
        member.organization_id = orgs[1].id
    elif problem == "suspended":
        user.is_suspended = True
    db.commit()
    monkeypatch.setattr("app.services.notifications.send_email", lambda *a, **k: pytest.fail("must not send email"))
    response = verify(client, user, "654321" if problem == "wrong_code" else "123456")
    assert response.status_code in (400, 403)
    assert not user.is_active and token.used_at is None
    assert db.query(Notification).count() == 0


def test_self_registration_roster_and_otp_gate(system, monkeypatch):
    client, db, users, orgs, resources, login = system
    sent = []
    monkeypatch.setattr("app.services.account_provisioning.send_otp_email", lambda *a, **k: sent.append(a))
    assert client.post("/auth/register", json={"email": "unknown@example.com", "password": "Password123!"}).status_code == 403
    member = CiteMember(full_name="Approved", email="approved@example.com", role="officer",
                        department_id=orgs[0].department_id, organization_id=orgs[0].id)
    db.add(member)
    db.commit()
    payload = {"email": member.email, "password": "Password123!"}
    response = client.post("/auth/register", json=payload)
    assert response.status_code == 201, response.text
    assert response.json()["is_active"] is False and response.json()["role"] == "officer"
    assert len(sent) == 1
    assert client.post("/auth/login", data={"username": member.email, "password": payload["password"]}).status_code == 403
    assert client.post("/auth/register", json=payload).status_code == 400


def test_resend_invalidates_old_code_and_failed_send_rolls_back(system, monkeypatch):
    client, db, *_ = system
    user, member, old = pending_registration(system)
    monkeypatch.setattr("app.routers.auth.generate_otp_code", lambda: "654321")
    monkeypatch.setattr("app.routers.auth.send_otp_email", lambda *a, **k: None)
    assert client.post("/auth/resend-otp", json={"email": user.email}).status_code == 200
    assert old.used_at is not None
    assert verify(client, user).status_code == 400
    fresh = db.query(OtpToken).filter(OtpToken.used_at.is_(None)).one()
    def fail(*a, **k):
        raise RuntimeError("offline")
    monkeypatch.setattr("app.routers.auth.send_otp_email", fail)
    assert client.post("/auth/resend-otp", json={"email": user.email}).status_code == 200
    db.refresh(fresh)
    assert fresh.used_at is None


def test_officer_can_read_own_notifications_but_not_another_users(system):
    client, db, users, orgs, resources, login = system
    notes = [Notification(user_id=users[role].id, kind="registration_confirmation", title="Approved", body="Welcome")
             for role in ("officer", "admin")]
    db.add_all(notes)
    db.commit()
    login("officer")
    assert [n["id"] for n in client.get("/notifications").json()] == [str(notes[0].id)]
    assert client.get("/notifications/unread-count").json() == {"unread_count": 1}
    assert client.patch(f"/notifications/{notes[1].id}/read").status_code == 404
    assert client.patch(f"/notifications/{notes[0].id}/read").status_code == 200
    assert client.patch(f"/notifications/{notes[0].id}/read").status_code == 200
    assert client.get("/notifications?unread_only=true").json() == []
    assert client.get("/notifications?limit=101").status_code == 422


@pytest.mark.parametrize("year", [None, "", "2026-2029", "2027-2026", "1899-1900"])
def test_event_creation_requires_valid_consecutive_year(system, year):
    client, db, users, orgs, resources, login = system
    login("admin")
    payload = {"title": "Event", "semester": "1st", "event_scope": "organizational"}
    if year is not None:
        payload["school_year"] = year
    assert client.post("/events", json=payload).status_code == 422


def test_event_year_saved_cannot_be_cleared_and_filter_is_scoped(system):
    client, db, users, orgs, resources, login = system
    login("admin")
    response = client.post("/events", json={"title": "New", "school_year": "2027-2028", "semester": "2nd", "event_scope": "organizational"})
    assert response.status_code == 201, response.text
    event_id = response.json()["id"]
    assert client.get(f"/events/{event_id}").json()["school_year"] == "2027-2028"
    for field in ("school_year", "semester", "event_scope"):
        assert client.patch(f"/events/{event_id}", json={field: None}).status_code == 422
    assert [e["id"] for e in client.get("/events?school_year=2027-2028").json()] == [event_id]
    assert client.get("/events/school-years").json() == ["2027-2028", "2026-2027"]


def test_legacy_year_repair_is_admin_only_scoped_and_audited(system):
    client, db, users, orgs, resources, login = system
    event = resources[0]["events"]
    event.school_year = None
    db.commit()
    payload = {"school_year": "2026-2027", "semester": "1st", "event_scope": "organizational"}
    endpoint = f"/events/{event.id}/academic-metadata"
    login("adviser")
    assert client.patch(endpoint, json=payload).status_code == 403
    login("admin")
    assert client.post(f"/events/{event.id}/approve", json={}).status_code == 409
    assert len(client.get("/events?missing_school_year=true").json()) == 1
    assert client.patch(f"/events/{resources[1]['events'].id}/academic-metadata", json=payload).status_code == 403
    assert client.patch(endpoint, json=payload).status_code == 200
    assert client.patch(endpoint, json=payload).status_code == 409
    assert db.query(AuditLog).filter(AuditLog.action == "event.academic_metadata_repaired").count() == 1


@pytest.mark.parametrize("format,content_type", [("pdf", "application/pdf"), ("csv", "text/csv"), ("html", "text/html")])
def test_exports_are_downloadable_scoped_and_printable(system, format, content_type):
    client, db, users, orgs, resources, login = system
    login("officer")
    event_id = resources[0]["events"].id
    paths = ["/reports/dashboard/export", f"/reports/event/{event_id}/export",
             f"/reports/category/{resources[0]['categories'].id}/export",
             "/reports/financial/export?period=school_year&school_year=2026-2027"]
    for path in paths:
        response = client.get(path + ("&" if "?" in path else "?") + f"format={format}")
        assert response.status_code == 200, response.text
        assert response.headers["content-type"].startswith(content_type)
        assert response.headers["cache-control"] == "no-store"
        if format == "pdf":
            assert response.content.startswith(b"%PDF-")
        elif format == "html":
            assert "@media print" in response.text
        if "/event/" in path or "/financial/" in path:
            if format != "pdf":
                assert "Event 1" not in response.text
    assert client.get(f"/reports/event/{resources[1]['events'].id}/export?format={format}").status_code == 403
    login("sds_staff")
    assert client.get("/reports/dashboard/export").status_code == 403
    client.headers.pop("Authorization")
    assert client.get("/reports/dashboard/export").status_code == 401


def test_export_manifest_and_invalid_report_filters(system):
    client, db, users, orgs, resources, login = system
    login("officer")
    manifest = client.get("/analytics/dashboard/exports")
    assert manifest.status_code == 200
    assert manifest.json()["dashboard"]["csv"] == "/reports/dashboard/export?format=csv"
    assert client.get("/reports/dashboard/export?format=exe").status_code == 422
    for path in ("/reports/financial", "/reports/financial.pdf", "/reports/financial/export"):
        assert client.get(path + "?period=school_year&school_year=2026-2029").status_code == 422


def test_csv_formula_injection_and_html_script_are_escaped():
    sections = [("Data", ["Name"], [["=HYPERLINK(\"evil\")"], ["<script>alert(1)</script>"]])]
    csv = render_export("Report", sections, "csv", "report").body.decode("utf-8-sig")
    assert "'=HYPERLINK" in csv
    html = render_export("Report", sections, "html", "report").body.decode()
    assert "<script>" not in html and "&lt;script&gt;" in html
