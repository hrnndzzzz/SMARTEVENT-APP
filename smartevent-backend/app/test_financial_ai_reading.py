"""The AI reading of the financial report sends figures only, and never stands in the report's way."""

import pytest

from app.config import settings
from app.routers import reports
from app.test_access_management import system

URL = "/reports/financial/ai-reading?period=school_year&school_year=2026-2027"
EMPTY = {"headline": None, "points": [], "suggestion": None}


@pytest.fixture
def gemini(monkeypatch):
    prompts = []

    def generate(contents, schema):
        prompts.append(contents)
        return {"headline": "Spending is on track.", "points": ["Supplies lead.", "", "b", "c", "d", "e"],
                "suggestion": "Get quotations early."}

    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(reports.ocr, "_generate", generate)
    reports._read.cache_clear()
    yield prompts
    reports._read.cache_clear()


def approve_all(db, resources):
    for r in resources:
        r["events"].status = "approved"
        r["expenses"].status = "approved"
    db.commit()


def test_the_reading_sends_figures_but_no_people_or_free_text_sources(system, gemini):
    client, db, users, orgs, resources, login = system
    approve_all(db, resources)
    login("treasurer")

    response = client.get(URL)

    assert response.status_code == 200, response.text
    assert response.json() == {"headline": "Spending is on track.", "points": ["Supplies lead.", "b", "c", "d"],
                               "suggestion": "Get quotations early."}
    [prompt] = gemini
    assert "Event 0" in prompt and "Supplies" in prompt
    assert "@example.com" not in prompt
    assert "Donation" not in prompt  # the free-text source; only its kind is sent


def test_the_reading_has_the_reports_own_checks(system, gemini):
    client, db, users, orgs, resources, login = system
    login("treasurer")
    assert client.get("/reports/financial/ai-reading?period=semester").status_code == 422
    assert client.get("/reports/financial/ai-reading?period=semester&school_year=2026-2027").status_code == 422


def test_no_key_or_a_failure_still_answers(system, gemini, monkeypatch):
    client, db, users, orgs, resources, login = system
    approve_all(db, resources)
    login("treasurer")
    monkeypatch.setattr(reports.ocr, "_generate", lambda *_: (_ for _ in ()).throw(RuntimeError("503")))
    assert client.get(URL).json() == EMPTY

    monkeypatch.setattr(settings, "gemini_api_key", None)
    assert client.get(URL).json() == EMPTY
    assert gemini == []
