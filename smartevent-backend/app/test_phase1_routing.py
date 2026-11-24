"""Compliance records and requirement presets.

This file used to cover institutional routing as well: a signatory per
step, each signing in turn after the Dean. The signatory role was removed
before the November defence — those people sign the printed Student
Activity Proposal — and `document_routing` went with it, so what is left
here is the compliance schema that shared the same phase of work.
"""

from datetime import datetime, timezone

import pytest
from sqlalchemy.exc import IntegrityError

from app.models import EventParticipant, EventRequirement, RequirementPreset, StudentComplianceRecord
from app.test_access_management import system


def test_compliance_schema_defaults_and_cross_event_constraints(system):
    client, db, users, orgs, resources, login = system
    event_ids = [resource["events"].id for resource in resources]
    participants = [EventParticipant(event_id=event_id, student_number="2026-001", full_name="Test Student") for event_id in event_ids]
    requirements = [EventRequirement(event_id=event_id, name="Consent", phase="pre_activity") for event_id in event_ids]
    db.add_all(participants + requirements)
    db.commit()
    record = StudentComplianceRecord(event_id=event_ids[0], participant_id=participants[0].id, requirement_id=requirements[0].id)
    db.add(record)
    db.commit()
    assert record.status == "MISSING"
    for participant, requirement in [(participants[1], requirements[0]), (participants[0], requirements[1])]:
        with pytest.raises(IntegrityError), db.begin_nested():
            db.add(StudentComplianceRecord(event_id=event_ids[0], participant_id=participant.id, requirement_id=requirement.id))
            db.flush()
    for invalid in ["CLEARED", "verified", "unknown"]:
        with pytest.raises(IntegrityError), db.begin_nested():
            record.status = invalid
            db.flush()
    with pytest.raises(IntegrityError), db.begin_nested():
        record.status = "VERIFIED"
        db.flush()
    record.reviewed_by = users["adviser"].id
    record.reviewed_at = datetime.now(timezone.utc)
    record.status = "VERIFIED"
    db.commit()
    assert record.status == "VERIFIED"
    with pytest.raises(IntegrityError), db.begin_nested():
        db.add(EventParticipant(event_id=event_ids[0], student_number="2026-001", full_name="Duplicate"))
        db.flush()


def test_requirement_presets_can_be_read_without_exposing_compliance_data(system):
    client, db, users, orgs, resources, login = system
    db.add(RequirementPreset(code="medical_clearance", name="Medical Clearance", phase="pre_activity", is_sensitive=True))
    db.commit()
    login("adviser")
    result = client.get("/events/requirement-presets")
    assert result.status_code == 200, result.text
    assert result.json()[0]["is_sensitive"] is True
