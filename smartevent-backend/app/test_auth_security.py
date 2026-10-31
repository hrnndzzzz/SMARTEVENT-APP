"""Authentication regressions use only SQLite and mocked delivery."""

from datetime import datetime, timedelta, timezone
from uuid import UUID

import pytest
from jose import jwt
from sqlalchemy import text

from app.config import settings
from app.models import AuditLog, OtpToken, User
from app.security import create_access_token, decode_access_token, hash_password, verify_password
from app.services.account_provisioning import create_user_with_temp_password
from app.services.otp import hash_otp_code
from app.test_access_management import system
from app.test_core_features import pending_registration


def add_code(db, user, purpose="password_reset", code="123456", **values):
    token = OtpToken(user_id=user.id, purpose=purpose, code_hash=hash_otp_code(code),
                     expires_at=datetime.now(timezone.utc) + timedelta(minutes=10), **values)
    db.add(token)
    db.commit()
    return token


@pytest.mark.parametrize("token_id", [
    "00000000-0000-0000-0000-000000000001",
    "68837025-5939-4654-8000-000000000000",
    "12345678-1234-4123-8123-123456789e12",
])
def test_sqlite_preserves_numeric_otp_uuid_on_reload(system, token_id):
    _, db, users, *_ = system
    expected_id = UUID(token_id)
    add_code(db, users["admin"], id=expected_id)
    assert db.execute(text("SELECT typeof(id) FROM otp_tokens")).scalar_one() == "text"
    db.expunge_all()
    stored = db.query(OtpToken).one()
    assert stored.id == expected_id
    assert db.get(OtpToken, expected_id) is stored


def test_current_account_exposes_assigned_organization_name_without_admin_lookup(system):
    client, db, users, organizations, _, login = system
    organizations[0].code = "LEGACY-123xyz"
    db.commit()
    login("officer")
    response = client.get("/auth/me")
    assert response.status_code == 200
    assert response.json()["organization_name"] == "Organization A"
    assert response.json()["organization_id"] == str(organizations[0].id)
    assert response.json()["department_name"] == "CITE"
    assert client.get("/organizations").status_code == 403
    login("super_admin")
    assert client.get("/auth/me").json()["organization_name"] is None


def reset(client, user, code="123456"):
    return client.post("/auth/reset-password", json={
        "email": user.email, "otp_code": code, "new_password": "Replacement-password!",
    })


@pytest.mark.parametrize("claim,value", [
    ("exp", None), ("iat", None), ("sub", None), ("aud", "other-api"), ("iss", "other-issuer"),
    ("iat", []), ("iat", True), ("iat", "123"), ("exp", float("inf")), ("sub", "invalid-uuid"),
])
def test_malformed_or_incomplete_tokens_are_unauthorized(system, claim, value):
    client, db, users, *_ = system
    claims = decode_access_token(create_access_token(str(users["officer"].id)))
    if value is None:
        claims.pop(claim)
    else:
        claims[claim] = value
    token = jwt.encode(claims, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
    assert client.get("/auth/me", headers={"Authorization": "Bearer " + token}).status_code == 401


def test_expired_and_future_tokens_are_rejected():
    assert decode_access_token(create_access_token("subject", expires_minutes=0)) is None
    claims = decode_access_token(create_access_token("subject"))
    claims["iat"] = datetime.now(timezone.utc).timestamp() + 300
    assert decode_access_token(jwt.encode(claims, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)) is None


@pytest.mark.parametrize("purpose", ["registration", "password_reset"])
def test_five_wrong_guesses_invalidate_otp(system, purpose):
    client, db, users, *_ = system
    if purpose == "registration":
        user, member, token = pending_registration(system)
        request = lambda code: client.post("/auth/verify-otp", json={"email": user.email, "otp_code": code})
    else:
        user = users["officer"]
        token = add_code(db, user)
        request = lambda code: reset(client, user, code)
    for _ in range(5):
        assert request("654321").status_code == 400
    db.refresh(token)
    assert token.failed_attempts == 5 and token.used_at is not None
    assert request("123456").status_code == 400


def test_reset_codes_are_replaced_and_requests_have_account_cooldown(system, monkeypatch):
    client, db, users, *_ = system
    user = users["officer"]
    old = add_code(db, user, created_at=datetime.now(timezone.utc) - timedelta(minutes=2))
    sent = []
    monkeypatch.setattr("app.services.account_provisioning.generate_otp_code", lambda: "654321")
    monkeypatch.setattr("app.services.account_provisioning.send_otp_email", lambda *a, **k: sent.append(a))
    response = client.post("/auth/forgot-password", json={"email": user.email})
    assert response.status_code == 200 and old.used_at is not None
    assert client.post("/auth/forgot-password", json={"email": user.email}).json() == response.json()
    assert len(sent) == 1
    assert reset(client, user).status_code == 400
    assert reset(client, user, "654321").status_code == 200
    assert reset(client, user, "654321").status_code == 400


def test_reset_revokes_sessions_and_all_outstanding_codes(system):
    client, db, users, _, _, login = system
    user = users["officer"]
    old_token = login("officer")
    add_code(db, user)
    add_code(db, user, "initial_setup", "654321")
    assert reset(client, user).status_code == 200
    assert db.query(OtpToken).filter(OtpToken.used_at.is_(None)).count() == 0
    assert client.get("/auth/me", headers={"Authorization": "Bearer " + old_token}).status_code == 401
    response = client.post("/auth/login", data={"username": user.email, "password": "Replacement-password!"})
    assert response.status_code == 200
    assert client.get("/auth/me", headers={"Authorization": "Bearer " + response.json()["access_token"]}).status_code == 200
    assert db.query(AuditLog).filter(AuditLog.action == "user.password_reset").count() == 1


@pytest.mark.parametrize("field", ["is_suspended", "is_active"])
def test_reset_does_not_bypass_disabled_account(system, monkeypatch, field):
    client, db, users, *_ = system
    user = users["officer"]
    token = add_code(db, user)
    setattr(user, field, field == "is_suspended")
    db.commit()
    monkeypatch.setattr("app.services.account_provisioning.send_otp_email", lambda *a, **k: pytest.fail("disabled account must not receive codes"))
    assert client.post("/auth/forgot-password", json={"email": user.email}).status_code == 200
    assert reset(client, user).status_code == 400
    assert token.used_at is None


def test_login_locks_after_five_failures_and_recovers_after_lock_expiry(system):
    client, db, users, *_ = system
    user = users["officer"]
    user.password_hash = hash_password("Current-password!")
    db.commit()
    for _ in range(5):
        assert client.post("/auth/login", data={"username": user.email, "password": "Wrong-password!"}).status_code == 401
    db.refresh(user)
    assert user.login_failed_attempts == 5 and user.login_locked_until is not None
    assert client.post("/auth/login", data={"username": user.email, "password": "Current-password!"}).status_code == 401
    user.login_locked_until = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()
    assert client.post("/auth/login", data={"username": user.email.upper(), "password": "Current-password!"}).status_code == 200
    assert user.login_failed_attempts == 0 and user.login_locked_until is None


def test_malformed_hash_and_missing_account_share_login_error(system):
    client, db, users, *_ = system
    responses = [client.post("/auth/login", data={"username": email, "password": "Wrong-password!"})
                 for email in (users["officer"].email, "unknown@example.com")]
    assert [response.status_code for response in responses] == [401, 401]
    assert responses[0].json() == responses[1].json()


def test_temporary_password_is_strong_and_cannot_change_after_expiry(system, monkeypatch):
    client, db, users, *_ = system
    sent = []
    monkeypatch.setattr("app.services.account_provisioning.send_otp_email", lambda *a, **k: sent.append(a))
    user = create_user_with_temp_password(db, full_name="Admin", email="NEW@example.com", role="super_admin")
    db.commit()
    temporary_password = sent[0][2]
    assert len(temporary_password) >= 32 and verify_password(temporary_password, user.password_hash)
    assert user.email == "new@example.com"
    response = client.post("/auth/login", data={"username": user.email, "password": temporary_password})
    assert response.status_code == 200
    assert response.json()["must_change_password"] is True
    client.headers["Authorization"] = "Bearer " + response.json()["access_token"]
    assert client.get("/auth/me").status_code == 403
    code = db.query(OtpToken).filter(OtpToken.user_id == user.id).one()
    code.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()
    assert client.post("/auth/change-password", json={"current_password": temporary_password,
                       "new_password": "New-permanent-password!"}).status_code == 401
    assert user.must_change_password


def test_login_bootstrap_retains_setup_guards_and_supports_relogin(system, monkeypatch):
    client, db, users, *_ = system
    sent = []
    monkeypatch.setattr("app.services.account_provisioning.send_otp_email", lambda *a, **k: sent.append(a))
    user = create_user_with_temp_password(db, full_name="Setup Admin",
        email="setup@example.com", role="admin", organization_id=users["admin"].organization_id,
        department_id=users["admin"].department_id)
    db.commit()
    temporary = sent[0][2]
    login = client.post("/auth/login", data={"username": user.email, "password": temporary})
    assert login.status_code == 200 and login.json()["must_change_password"] is True
    client.headers["Authorization"] = "Bearer " + login.json()["access_token"]
    assert client.get("/auth/me").status_code == 403
    assert client.get("/events").status_code == 403
    changed = client.post("/auth/change-password", json={
        "current_password": temporary, "new_password": "Permanent-password-123!",
    })
    assert changed.status_code == 200 and changed.json()["must_change_password"] is False
    assert client.get("/auth/me").status_code == 401
    relogin = client.post("/auth/login", data={"username": user.email, "password": "Permanent-password-123!"})
    assert relogin.status_code == 200 and relogin.json()["must_change_password"] is False
    client.headers["Authorization"] = "Bearer " + relogin.json()["access_token"]
    assert client.get("/auth/me").status_code == 200


def test_password_change_invalidates_old_session_and_pending_reset(system):
    client, db, users, _, _, login = system
    user = users["officer"]
    user.password_hash = hash_password("Current-password!")
    db.commit()
    login("officer")
    add_code(db, user)
    assert client.post("/auth/change-password", json={"current_password": "Current-password!",
                       "new_password": "New-permanent-password!"}).status_code == 200
    assert client.get("/auth/me").status_code == 401
    assert reset(client, user).status_code == 400
    assert db.query(AuditLog).filter(AuditLog.action == "user.password_changed").count() == 1


def test_wrong_current_password_keeps_the_session(system):
    client, db, users, _, _, login = system
    user = users["officer"]
    user.password_hash = hash_password("Current-password!")
    db.commit()
    login("officer")
    response = client.post("/auth/change-password", json={"current_password": "Wrong-password!",
                           "new_password": "New-permanent-password!"})
    assert response.status_code == 400
    assert client.get("/auth/me").status_code == 200


def test_provisioning_errors_do_not_expose_provider_secrets(system, monkeypatch):
    client, db, users, _, _, login = system
    login("super_admin")
    def fail(*args, **kwargs):
        raise RuntimeError("provider key super-secret-token")
    monkeypatch.setattr("app.services.account_provisioning.send_otp_email", fail)
    response = client.post("/auth/register/sds", json={"full_name": "SDS", "email": "sds-new@example.com"})
    assert response.status_code == 503
    assert "super-secret-token" not in response.text
    assert db.query(User).filter(User.email == "sds-new@example.com").first() is None


def test_verification_status_requires_valid_code_even_after_activation(system):
    client, db, users, *_ = system
    user = users["officer"]
    token = add_code(db, user, "registration", used_at=datetime.now(timezone.utc))
    payload = {"email": user.email, "otp_code": "654321"}
    responses = [client.post("/auth/verify-otp", json=payload)]
    user.is_suspended = True
    db.commit()
    responses.append(client.post("/auth/verify-otp", json=payload))
    responses.append(client.post("/auth/verify-otp", json={**payload, "email": "unknown@example.com"}))
    assert all(response.status_code == 400 for response in responses)
    assert len({response.text for response in responses}) == 1
    user.is_suspended = False
    db.commit()
    assert client.post("/auth/verify-otp", json={**payload, "otp_code": "123456"}).status_code == 200
    token.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()
    assert client.post("/auth/verify-otp", json={**payload, "otp_code": "123456"}).status_code == 400
