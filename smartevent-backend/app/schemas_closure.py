from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import Field

from app.schemas_compliance import Input


class EventCompletion(Input):
    completed_on: date
    remarks: str = Field(min_length=1, max_length=2000)


class ParallelAssignment(Input):
    participant_id: UUID
    title: str = Field(min_length=1, max_length=200)
    learning_objectives: str = Field(min_length=1, max_length=3000)
    instructions: str = Field(min_length=1, max_length=5000)
    reason: str = Field(min_length=1, max_length=2000)
    due_date: date | None = None
    version: int = Field(default=0, ge=0)


class ParticipationUpdate(Input):
    participation_mode: Literal["attending"]
    remarks: str = Field(min_length=1, max_length=2000)
