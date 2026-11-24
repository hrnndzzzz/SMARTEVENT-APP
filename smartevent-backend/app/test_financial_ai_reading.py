"""The AI reading of the financial report sends figures only, and never stands in the report's way."""

from datetime import date

import pytest

from app.config import settings
from app.routers import reports
from app.test_access_management import system

URL = "/reports/financial/ai-reading?period=school_year&school_year=2026-2027"
EMPTY = {"headline": None, "happened": [], "causes": [], "outlook": [], "actions": []}


@pytest.fixture
def gemini(monkeypatch):
    prompts = []

    def generate(contents, schema):
        prompts.append(contents)
        return {"headline": "Spending is on track.", "happened": ["Supplies lead.", "", "b", "c", "d"],
                "causes": ["Event 0 bought supplies."], "outlook": "not a list",
                "actions": ["Get quotations early."]}

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
    login("officer")

    response = client.get(URL)

    assert response.status_code == 200, response.text
    assert response.json() == {"headline": "Spending is on track.", "happened": ["Supplies lead.", "b", "c"],
                               "causes": ["Event 0 bought supplies."], "outlook": [],
                               "actions": ["Get quotations early."]}
    [prompt] = gemini
    assert "Event 0" in prompt and "Supplies" in prompt
    assert "@example.com" not in prompt
    assert "Donation" not in prompt  # the free-text source; only its kind is sent


def test_the_reading_has_the_reports_own_checks(system, gemini):
    client, db, users, orgs, resources, login = system
    login("officer")
    assert client.get("/reports/financial/ai-reading?period=semester").status_code == 422
    assert client.get("/reports/financial/ai-reading?period=semester&school_year=2026-2027").status_code == 422


def test_no_key_or_a_failure_still_answers(system, gemini, monkeypatch):
    client, db, users, orgs, resources, login = system
    approve_all(db, resources)
    login("officer")
    monkeypatch.setattr(reports.ocr, "_generate", lambda *_: (_ for _ in ()).throw(RuntimeError("503")))
    assert client.get(URL).json() == EMPTY

    monkeypatch.setattr(settings, "gemini_api_key", None)
    assert client.get(URL).json() == EMPTY
    assert gemini == []


def test_the_outlook_gets_the_pace_and_the_events_still_ahead_worked_out():
    def event(title, status, when, budget, spent):
        return reports.FinancialEventSummary(
            event_id="00000000-0000-0000-0000-000000000001", title=title, school_year=None, semester=None,
            event_scope=None, income_count=0, expense_count=0, total_income=0, total_expenses=0, net_balance=0,
            status=status, event_date=when, allocated_budget=budget, spent_to_date=spent)

    report = reports.ConsolidatedFinancialReport(
        period="monthly", start_date=date(2026, 11, 1), end_date=date(2026, 11, 30), school_year=None,
        semester=None, event_scope=None, total_income=100, total_expenses=300, unassigned_expense_total=0,
        net_balance=-200, events=[event("Ahead", "approved", date(2026, 12, 5), 1000, 250),
                                  event("Over budget", "approved", date(2026, 12, 6), 100, 400),
                                  event("Past", "approved", date(2026, 11, 2), 900, 0),
                                  event("Waiting", "pending", date(2026, 12, 9), 900, 0)])

    lines = reports._outlook_lines(report, today=date(2026, 11, 10))

    assert lines == ["Pace: 10 of 30 days passed; at this pace the period ends at income 300.00, spending 900.00",
                     "Approved events still ahead: 2, with 750.00 of budget not yet spent"]
    assert reports._outlook_lines(report, today=date(2026, 11, 30))[0].startswith("Approved events")  # period done
