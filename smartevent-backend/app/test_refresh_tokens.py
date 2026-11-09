"""A device's renewal key: a fresh access token without the password, until it is ended."""

from datetime import datetime, timedelta, timezone

import pytest

from app.models import RefreshToken
from app.security import decode_access_token, hash_password
from app.test_access_management import system

PASSWORD = "Correct-horse-battery-1"


def sign_in(client, db, user):
    user.password_hash = hash_password(PASSWORD)
    db.commit()
    client.headers.pop("Authorization", None)
    response = client.post("/auth/login", data={"username": user.email, "password": PASSWORD})
    assert response.status_code == 200, response.text
    return response.json()


def renew(client, key):
    client.headers.pop("Authorization", None)
    return client.post("/auth/refresh", json={"refresh_token": key})


def test_a_renewal_key_brings_a_fresh_token_and_stays_valid(system):
    client, db, users, *_ = system
    key = sign_in(client, db, users["treasurer"])["refresh_token"]
    stored = db.query(RefreshToken).one()
    assert stored.token_hash != key  # only the hash is kept
    stored.expires_at = datetime.now(timezone.utc) + timedelta(days=1)
    db.commit()

    first = renew(client, key)
    assert first.status_code == 200, first.text
    assert decode_access_token(first.json()["access_token"])["sub"] == str(users["treasurer"].id)
    # Not rotated, so a reply lost on a weak connection costs nothing.
    assert first.json()["refresh_token"] == key
    assert renew(client, key).status_code == 200
    db.refresh(stored)
    expires = stored.expires_at.replace(tzinfo=stored.expires_at.tzinfo or timezone.utc)
    assert expires > datetime.now(timezone.utc) + timedelta(days=29)  # moved forward on use
    client.headers["Authorization"] = "Bearer " + first.json()["access_token"]
    assert client.get("/auth/me").status_code == 200


@pytest.mark.parametrize("ending", ["logout", "password_change", "suspended", "expired", "unknown"])
def test_an_ended_renewal_key_is_refused(system, ending):
    client, db, users, *_ = system
    user = users["treasurer"]
    signed_in = sign_in(client, db, user)
    key = signed_in["refresh_token"]
    if ending == "logout":
        assert client.post("/auth/logout", json={"refresh_token": key}).status_code == 204
    elif ending == "password_change":
        client.headers["Authorization"] = "Bearer " + signed_in["access_token"]
        changed = client.post("/auth/change-password", json={
            "current_password": PASSWORD, "new_password": "Another-horse-battery-2"})
        assert changed.status_code == 200, changed.text
    elif ending == "suspended":
        user.is_suspended = True
        db.commit()
    elif ending == "expired":
        db.query(RefreshToken).one().expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
        db.commit()
    else:
        key = "not-a-key-anyone-was-given"
    response = renew(client, key)
    assert response.status_code == 401 and response.json()["detail"] == "Sign in again"


def test_signing_in_still_works_before_the_migration_is_applied(system):
    client, db, users, *_ = system
    RefreshToken.__table__.drop(db.get_bind())
    try:
        signed_in = sign_in(client, db, users["treasurer"])
        assert signed_in["refresh_token"] is None and signed_in["access_token"]
        client.headers["Authorization"] = "Bearer " + signed_in["access_token"]
        changed = client.post("/auth/change-password", json={
            "current_password": PASSWORD, "new_password": "Another-horse-battery-2"})
        assert changed.status_code == 200, changed.text
    finally:
        RefreshToken.__table__.create(db.get_bind())


def test_a_temporary_password_gets_no_renewal_key(system):
    client, db, users, *_ = system
    user = users["officer"]
    user.password_hash = hash_password(PASSWORD)
    user.must_change_password = True
    db.commit()
    from app.test_auth_security import add_code
    add_code(db, user, purpose="initial_setup")
    response = client.post("/auth/login", data={"username": user.email, "password": PASSWORD})
    assert response.status_code == 200, response.text
    assert response.json()["refresh_token"] is None
    assert db.query(RefreshToken).count() == 0
