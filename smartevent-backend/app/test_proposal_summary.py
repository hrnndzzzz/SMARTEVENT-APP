"""The AI-written proposal summary reads only remarks the caller may see."""

from datetime import datetime, timezone

import pytest

from app.config import settings
from app.models import Approval, AuditLog
from app.routers import analytics
from app.test_access_management import system


@pytest.fixture
def gemini(monkeypatch):
    prompts = []

    def generate(contents, schema):
        prompts.append(contents)
        return {"accepted": "Budgets matched.", "rejected": "Budgets did not add up."}

    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(analytics.ocr, "_generate", generate)
    analytics._summarise.cache_clear()
    yield prompts
    analytics._summarise.cache_clear()


def decide(db, event, decision, remarks, reviewer):
    db.add(Approval(entity_type="event", entity_id=event.id, step_order=1, reviewer_id=reviewer.id,
                    decision=decision, remarks=remarks, decided_at=datetime.now(timezone.utc)))


def test_the_summary_reads_only_the_callers_own_remarks(system, gemini):
    client, db, users, orgs, resources, login = system
    ours, theirs = resources[0]["events"], resources[1]["events"]
    decide(db, ours, "approved", "Clear program flow", users["admin"])
    decide(db, ours, "rejected", "Quotation missing for catering", users["admin"])
    decide(db, theirs, "rejected", "Organization B secret remark", users["admin"])
    db.add(AuditLog(action="sap_rejected", entity_type="events", entity_id=ours.id,
                    details={"revision": 1, "remarks": "Clearance not attached"}))
    db.commit()

    login("adviser")  # Organization A's
    response = client.get("/analytics/proposal-summary")

    assert response.status_code == 200, response.text
    assert response.json() == {"accepted": "Budgets matched.", "rejected": "Budgets did not add up."}
    [prompt] = gemini
    assert "Clear program flow" in prompt and "Quotation missing" in prompt and "Clearance not attached" in prompt
    assert "Organization B" not in prompt


def test_no_remarks_or_no_key_means_no_summary(system, gemini, monkeypatch):
    client, db, users, orgs, resources, login = system
    login("adviser")
    assert client.get("/analytics/proposal-summary").json() == {"accepted": None, "rejected": None}

    decide(db, resources[0]["events"], "rejected", "Dates too close", users["admin"])
    db.commit()
    monkeypatch.setattr(settings, "gemini_api_key", None)
    assert client.get("/analytics/proposal-summary").json() == {"accepted": None, "rejected": None}
    assert gemini == []


def test_a_gemini_failure_still_answers(system, gemini, monkeypatch):
    client, db, users, orgs, resources, login = system
    decide(db, resources[0]["events"], "rejected", "Dates too close", users["admin"])
    db.commit()
    monkeypatch.setattr(analytics.ocr, "_generate", lambda *_: (_ for _ in ()).throw(RuntimeError("503")))
    login("adviser")
    response = client.get("/analytics/proposal-summary")
    assert response.status_code == 200
    # Only the side that had remarks would have had text; neither does after a failure.
    assert response.json() == {"accepted": None, "rejected": None}
