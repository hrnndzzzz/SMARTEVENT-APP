"""Tests for the event reporting dimensions introduced in Priority 2."""

from datetime import datetime
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.schemas import EventCreate, EventOut, EventUpdate


def valid_event_payload():
    return {
        "title": "Student leadership seminar",
        "school_year": "2025-2026",
        "semester": "1st",
        "event_scope": "departmental",
    }


def test_event_requires_school_year_semester_and_scope():
    event = EventCreate(**valid_event_payload())

    assert event.school_year == "2025-2026"
    assert event.semester == "1st"
    assert event.event_scope == "departmental"


@pytest.mark.parametrize(
    "school_year",
    ["2025", "2025/2026", "25-2026", "2025-202", "2025-2027-"],
)
def test_event_rejects_invalid_school_year_format(school_year):
    with pytest.raises(ValidationError):
        EventCreate(**{**valid_event_payload(), "school_year": school_year})


@pytest.mark.parametrize("semester", ["first", "second", "3rd"])
def test_event_rejects_unknown_semester(semester):
    with pytest.raises(ValidationError):
        EventCreate(**{**valid_event_payload(), "semester": semester})


@pytest.mark.parametrize("event_scope", ["department", "organization", "public"])
def test_event_rejects_unknown_scope(event_scope):
    with pytest.raises(ValidationError):
        EventCreate(**{**valid_event_payload(), "event_scope": event_scope})


def test_event_update_allows_reporting_dimensions_to_be_changed():
    update = EventUpdate(
        school_year="2026-2027",
        semester="2nd",
        event_scope="organizational",
    )

    assert update.school_year == "2026-2027"
    assert update.semester == "2nd"
    assert update.event_scope == "organizational"


def test_event_response_accepts_legacy_pending_adviser_status():
    event = EventOut(
        id=uuid4(),
        department_id=uuid4(),
        category_id=None,
        school_year="2025-2026",
        semester="1st",
        event_scope="departmental",
        title="Pending event",
        description=None,
        proposed_by=uuid4(),
        status="pending_adviser",
        event_date=None,
        estimated_cost=0,
        allocated_budget=0,
        remaining_budget=0,
        created_at=datetime.now(),
        updated_at=datetime.now(),
    )

    assert event.status == "pending_adviser"
