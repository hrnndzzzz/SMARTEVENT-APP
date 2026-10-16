"""Phase 2 contracts do not expose private object references or authentication secrets."""

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas import AccountEmail


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class LogisticsUpdate(Input):
    activity_location: Literal["on_campus", "off_campus"]
    destination: str = Field(min_length=1, max_length=300)
    transport_mode: Literal["none", "institution", "third_party"]
    transport_notes: str | None = Field(default=None, max_length=2000)


class ParticipantCreate(Input):
    student_number: str = Field(min_length=1, max_length=50)
    full_name: str = Field(min_length=1, max_length=150)
    email: AccountEmail | None = None

    @field_validator("student_number")
    @classmethod
    def normalize_number(cls, value):
        return value.upper()


class ParticipantUpdate(Input):
    full_name: str = Field(min_length=1, max_length=150)
    email: AccountEmail | None = None
    is_active: bool


class ParticipantOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    event_id: uuid.UUID
    student_number: str
    full_name: str
    email: str | None
    is_active: bool
    participation_mode: Literal["attending", "parallel"]


class PersonnelCreate(Input):
    staff_reference: str = Field(min_length=1, max_length=50)
    full_name: str = Field(min_length=1, max_length=150)
    position: str = Field(min_length=1, max_length=100)
    qualifications: str = Field(min_length=1, max_length=1000)
    institution_employee_confirmed: Literal[True]

    @field_validator("staff_reference")
    @classmethod
    def normalize_reference(cls, value):
        return value.upper()


class VehicleCreate(Input):
    plate_number: str = Field(min_length=1, max_length=30)
    operator_name: str = Field(min_length=1, max_length=150)
    driver_name: str = Field(min_length=1, max_length=150)
    out_of_line: bool = False

    @field_validator("plate_number")
    @classmethod
    def normalize_plate(cls, value):
        value = "".join(value.upper().split()).replace("-", "")
        if not value or not value.isalnum():
            raise ValueError("Use letters and numbers for the plate number")
        return value


class ActiveUpdate(Input):
    is_active: bool


class RequirementCreate(Input):
    preset_id: uuid.UUID | None = None
    name: str = Field(min_length=1, max_length=150)
    description: str | None = Field(default=None, max_length=2000)
    is_required: bool = True
    requires_notarization: bool = False
    is_sensitive: bool = False


class RequirementRequiredUpdate(Input):
    is_required: bool


class VersionedRecord(Input):
    id: uuid.UUID
    version: int = Field(ge=1)


class BatchReview(Input):
    records: list[VersionedRecord] = Field(min_length=1, max_length=100)
    decision: Literal["VERIFIED", "REJECTED"]
    evidence_mode: Literal["digital", "physical"]
    notarization_confirmed: bool = False
    remarks: str = Field(min_length=1, max_length=2000)

    @field_validator("records")
    @classmethod
    def unique_records(cls, value):
        if len({record.id for record in value}) != len(value):
            raise ValueError("Select each compliance record only once")
        return value


class DocumentReview(Input):
    version: int = Field(ge=1)
    decision: Literal["VERIFIED", "REJECTED"]
    remarks: str = Field(min_length=1, max_length=2000)
    validity_confirmed: bool = False


class ComplianceRecordOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    participant_id: uuid.UUID
    requirement_id: uuid.UUID
    status: str
    version: int
    evidence_mode: str | None
    notarization_confirmed: bool
    submitted_at: datetime | None
    reviewed_at: datetime | None
    reviewed_by: uuid.UUID | None
    remarks: str | None
