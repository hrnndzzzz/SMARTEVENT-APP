"""Requests for the app from the public website, and the department deciding them.

The form is the only route in the system a member of the public can
reach, so these tests care as much about what it refuses and what it
declines to say back as about the happy path.
"""

import pytest

from app.config import settings
from app.models import AuditLog, DownloadRequest, Notification
from app.services.email import EmailError
from app.test_access_management import system  # noqa: F401 — fixture


def form(**changes):
    return {
        "name": "Rhea Santos", "email": "rhea@example.com", "organization": "CITE Student Council",
        "role": "officer", "reason": "We want to track our event budget this semester.",
        **changes,
    }


def anonymous(client):
    """The form posts from a browser with no account, so no token."""
    client.headers.pop("Authorization", None)
    return client


def test_a_visitor_can_ask_and_is_told_only_that_it_was_received(system):  # noqa: F811
    client, db, users, orgs, resources, login = system
    response = anonymous(client).post("/download-requests", json=form())
    assert response.status_code == 201, response.text

    # What comes back reaches the public internet, so it carries a status
    # and a sentence — not the row, not an id to guess at.
    assert response.json() == {
        "status": "pending",
        "message": ("Request received. If the department approves it, the download link goes "
                    "to this address."),
    }

    row = db.query(DownloadRequest).one()
    assert (row.name, row.email, row.status, row.email_status) == (
        "Rhea Santos", "rhea@example.com", "pending", "not_sent")
    assert row.decided_by is None and row.decided_at is None


def test_the_same_address_cannot_queue_twice_but_may_ask_again_once_decided(system):  # noqa: F811
    client, db, users, orgs, resources, login = system
    assert anonymous(client).post("/download-requests", json=form()).status_code == 201

    # The second one is refused by the database's partial index, which is
    # what makes the website's 409 true rather than hopeful.
    again = client.post("/download-requests", json=form(name="Rhea S."))
    assert again.status_code == 409
    assert again.json()["detail"] == "There is already a request from this address waiting"

    # Capitalisation is not a new person.
    assert client.post("/download-requests", json=form(email="RHEA@example.com")).status_code == 409

    login("admin")
    request_id = str(db.query(DownloadRequest).one().id)
    assert client.post(f"/download-requests/{request_id}/decide",
                       json={"approve": False, "note": "Not a member organization"}).status_code == 200

    # Decided, so the address is free to ask again — a refusal is not a ban.
    assert anonymous(client).post("/download-requests", json=form()).status_code == 201
    assert db.query(DownloadRequest).count() == 2


def test_every_administrator_is_told_and_nobody_else_is(system):  # noqa: F811
    client, db, users, orgs, resources, login = system
    assert anonymous(client).post("/download-requests", json=form()).status_code == 201

    notices = db.query(Notification).filter(Notification.kind == 'download_request').all()
    told = {notice.user_id for notice in notices}
    assert told == {users["admin"].id, users["super_admin"].id}, (
        'the request reached the wrong people, or nobody')
    assert users["officer"].id not in told and users["treasurer"].id not in told

    one = notices[0]
    assert one.title == 'App download requested'
    assert 'Rhea Santos' in one.body and 'CITE Student Council' in one.body
    # Openable: the notice names the request it is about.
    assert one.payload['download_request_id'] == str(db.query(DownloadRequest).one().id)
    # There is no email behind this notice, so it is not left looking owed.
    assert one.email_status == 'sent'


def test_a_suspended_administrator_is_not_told(system):  # noqa: F811
    client, db, users, orgs, resources, login = system
    users["admin"].is_suspended = True
    db.commit()

    assert anonymous(client).post("/download-requests", json=form()).status_code == 201
    told = {notice.user_id for notice in
            db.query(Notification).filter(Notification.kind == 'download_request').all()}
    assert told == {users["super_admin"].id}


def test_reading_and_deciding_are_administrators_only(system):  # noqa: F811
    client, db, users, orgs, resources, login = system
    assert anonymous(client).post("/download-requests", json=form()).status_code == 201
    request_id = str(db.query(DownloadRequest).one().id)

    for role in ("officer", "treasurer", "adviser", "sds_staff"):
        login(role)
        assert client.get("/download-requests").status_code == 403, role
        assert client.get("/download-requests/pending-count").status_code == 403, role
        assert client.post(f"/download-requests/{request_id}/decide",
                           json={"approve": True}).status_code == 403, role

    # Still pending after all of that.
    db.expire_all()
    assert db.query(DownloadRequest).one().status == 'pending'

    login("admin")
    listed = client.get("/download-requests")
    assert listed.status_code == 200
    assert [row["email"] for row in listed.json()] == ["rhea@example.com"]
    assert client.get("/download-requests/pending-count").json() == {"pending_count": 1}
    assert client.get("/download-requests?status=approved").json() == []


def test_approving_records_who_decided_and_leaves_an_audit_trail(system):  # noqa: F811
    client, db, users, orgs, resources, login = system
    assert anonymous(client).post("/download-requests", json=form()).status_code == 201
    request_id = str(db.query(DownloadRequest).one().id)

    login("admin")
    decided = client.post(f"/download-requests/{request_id}/decide",
                          json={"approve": True, "note": "Known officer"})
    assert decided.status_code == 200, decided.text
    body = decided.json()
    assert body["status"] == "approved"
    assert body["decided_by"] == str(users["admin"].id)
    assert body["decided_at"] is not None
    assert body["note"] == "Known officer"

    entry = db.query(AuditLog).filter(AuditLog.action == 'download_request_approved').one()
    assert entry.user_id == users["admin"].id
    assert entry.entity_type == 'download_requests'
    assert entry.details["email"] == 'rhea@example.com'

    # Once only: a second decision would overwrite a record of the first.
    stale = client.post(f"/download-requests/{request_id}/decide", json={"approve": False, "note": "No"})
    assert stale.status_code == 409
    assert stale.json()["detail"] == "This request was already approved"
    assert client.get("/download-requests/pending-count").json() == {"pending_count": 0}


def test_a_refusal_has_to_say_why(system):  # noqa: F811
    client, db, users, orgs, resources, login = system
    assert anonymous(client).post("/download-requests", json=form()).status_code == 201
    request_id = str(db.query(DownloadRequest).one().id)

    login("admin")
    # "Rejected" with nothing against it is not something anyone can act
    # on in a month's time.
    for note in (None, "", "   "):
        payload = {"approve": False} if note is None else {"approve": False, "note": note}
        assert client.post(f"/download-requests/{request_id}/decide", json=payload).status_code == 422

    # An approval needs no words.
    assert client.post(f"/download-requests/{request_id}/decide", json={"approve": True}).status_code == 200


def test_the_link_is_emailed_on_approval_when_there_is_somewhere_to_point(system, monkeypatch):  # noqa: F811
    client, db, users, orgs, resources, login = system
    sent = []
    monkeypatch.setattr("app.routers.download_requests.send_download_link_email",
                        lambda to, name, url: sent.append((to, name, url)))
    monkeypatch.setattr(settings, "app_download_url", "https://github.com/x/y/releases")

    assert anonymous(client).post("/download-requests", json=form()).status_code == 201
    login("admin")
    request_id = str(db.query(DownloadRequest).one().id)
    decided = client.post(f"/download-requests/{request_id}/decide", json={"approve": True})

    assert decided.json()["email_status"] == "sent"
    assert sent == [("rhea@example.com", "Rhea Santos", "https://github.com/x/y/releases")]


def test_no_download_url_configured_means_the_approval_still_stands(system, monkeypatch):  # noqa: F811
    client, db, users, orgs, resources, login = system
    monkeypatch.setattr(settings, "app_download_url", None)
    monkeypatch.setattr("app.routers.download_requests.send_download_link_email",
                        lambda *args: pytest.fail("nothing to point at, so nothing should be sent"))

    assert anonymous(client).post("/download-requests", json=form()).status_code == 201
    login("admin")
    request_id = str(db.query(DownloadRequest).one().id)
    decided = client.post(f"/download-requests/{request_id}/decide", json={"approve": True})

    assert decided.json()["status"] == "approved"
    # Recorded as still owed, so the department can send it by hand.
    assert decided.json()["email_status"] == "not_sent"


@pytest.mark.parametrize("failure", [EmailError("down"), RuntimeError("Resend is not configured")])
def test_a_failed_email_does_not_undo_the_decision(system, monkeypatch, failure):  # noqa: F811
    client, db, users, orgs, resources, login = system

    def explode(*args):
        raise failure

    monkeypatch.setattr("app.routers.download_requests.send_download_link_email", explode)
    monkeypatch.setattr(settings, "app_download_url", "https://github.com/x/y/releases")

    assert anonymous(client).post("/download-requests", json=form()).status_code == 201
    login("admin")
    request_id = str(db.query(DownloadRequest).one().id)
    decided = client.post(f"/download-requests/{request_id}/decide", json={"approve": True})

    assert decided.status_code == 200, decided.text
    # The decision is the department's and does not depend on a mailer.
    assert decided.json()["status"] == "approved"
    assert decided.json()["email_status"] == "failed"


@pytest.mark.parametrize("bad", [
    form(email="not-an-address"),
    form(name="R"),
    form(organization=""),
    form(reason="too short"),
    form(role=""),
    {**form(), "approved": True},  # A field the form does not get to set.
])
def test_the_form_refuses_what_it_cannot_use(system, bad):  # noqa: F811
    client, db, users, orgs, resources, login = system
    assert anonymous(client).post("/download-requests", json=bad).status_code == 422
    assert db.query(DownloadRequest).count() == 0


def test_the_public_form_is_rate_limited_in_its_own_words(system):  # noqa: F811
    client, db, users, orgs, resources, login = system
    anonymous(client)
    # Thirty go through the limiter; each is refused as a duplicate after
    # the first, which is fine — the limiter runs before the route.
    for index in range(30):
        assert client.post("/download-requests", json=form()).status_code in {201, 409}

    stopped = client.post("/download-requests", json=form())
    assert stopped.status_code == 429
    # "Authentication" would be a lie here, and a visitor reads this.
    assert stopped.json()["detail"] == "Too many requests"
    assert stopped.headers["Retry-After"]
