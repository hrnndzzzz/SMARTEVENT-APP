"""The AI budget suggestion compares only past events the caller may see, and keeps only what it was shown."""

from datetime import date

import pytest

from app.config import settings
from app.models import Event, Expense
from app.routers import recommendations
from app.test_access_management import system


@pytest.fixture
def gemini(monkeypatch):
    prompts, answer = [], {"amount": 1500, "reason": "Like the fair.", "similar_event_numbers": [1, 99, 1]}

    def generate(contents, schema):
        prompts.append(contents)
        return dict(answer)

    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(recommendations.ocr, "_generate", generate)
    recommendations._suggest.cache_clear()
    yield prompts, answer
    recommendations._suggest.cache_clear()


def past_event(db, users, org, category, title, budget, spent):
    event = Event(organization_id=org.id, department_id=org.department_id, title=title, status="completed",
                  proposed_by=users["treasurer"].id, allocated_budget=budget, remaining_budget=0)
    db.add(event)
    db.flush()
    db.add(Expense(organization_id=org.id, department_id=org.department_id, event_id=event.id, category_id=category.id,
                   description="Spent", amount=spent, expense_date=date.today(),
                   recorded_by=users["treasurer"].id, status="approved"))
    return event


def ask(client, **body):
    response = client.post("/recommendations/event-budget/ai", json={"title": "Science Fair", **body})
    assert response.status_code == 200, response.text
    return response.json()


def test_the_suggestion_cites_only_events_it_was_shown(system, gemini, monkeypatch):
    client, db, users, orgs, resources, login = system
    prompts, _ = gemini
    for event in (r["events"] for r in resources):
        event.status = "completed"  # Event 0 in Organization A, Event 1 in Organization B
    db.commit()
    past_event(db, users, orgs[0], resources[0]["categories"], "Math Fair", 1200, 900)
    db.commit()
    login("treasurer")  # Organization A's

    body = ask(client)

    [prompt] = prompts
    assert "Event 0" in prompt and "Math Fair" in prompt and "Event 1" not in prompt
    assert body["amount"] == 1500 and body["reason"] == "Like the fair."
    # 99 was never listed, and the repeated 1 counts once.
    [similar] = body["similar_events"]
    assert f"1. {similar['title']} (budget" in prompt


def test_too_few_events_no_key_or_a_bad_answer_suggests_nothing(system, gemini, monkeypatch):
    client, db, users, orgs, resources, login = system
    prompts, answer = gemini
    login("treasurer")
    assert ask(client)["amount"] is None and prompts == []  # no past events at all

    past_event(db, users, orgs[0], resources[0]["categories"], "Math Fair", 1200, 900)
    past_event(db, users, orgs[0], resources[0]["categories"], "Art Fair", 800, 700)
    db.commit()
    answer["amount"] = "lots"
    assert ask(client)["amount"] is None

    monkeypatch.setattr(settings, "gemini_api_key", None)
    assert ask(client, title="Another fair") == {"amount": None, "reason": None, "similar_events": []}


def test_a_gemini_failure_still_answers(system, gemini, monkeypatch):
    client, db, users, orgs, resources, login = system
    past_event(db, users, orgs[0], resources[0]["categories"], "Math Fair", 1200, 900)
    past_event(db, users, orgs[0], resources[0]["categories"], "Art Fair", 800, 700)
    db.commit()
    monkeypatch.setattr(recommendations.ocr, "_generate", lambda *_: (_ for _ in ()).throw(RuntimeError("503")))
    login("treasurer")
    assert ask(client) == {"amount": None, "reason": None, "similar_events": []}
