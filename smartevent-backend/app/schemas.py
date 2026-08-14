"""
Pydantic schemas — these define what JSON goes IN and OUT of the API.
Kept separate from models.py (the DB layer) on purpose: it lets you
return a trimmed-down UserOut (no password_hash!) while User the ORM
model still has that column internally.
"""

import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, ConfigDict, Field

Role = Literal["admin", "adviser", "officer"]


# ---- Auth / Users --------------------------------------------------------

class UserCreate(BaseModel):
    full_name: str = Field(min_length=1, max_length=150)
    email: EmailStr
    password: str = Field(min_length=8, description="Min 8 characters")
    role: Role
    position: str | None = None


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    email: EmailStr
    role: Role
    position: str | None
    is_active: bool
    created_at: datetime


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class TokenData(BaseModel):
    user_id: str | None = None


# ---- Categories -----------------------------------------------------------

class CategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    allocated_budget: float = Field(ge=0, default=0)
    low_balance_threshold: float = Field(ge=0, default=0)


class CategoryUpdate(BaseModel):
    """
    All fields optional — PATCH semantics. Only fields the caller
    actually sends get changed; everything else stays as-is.
    Deliberately does NOT include remaining_budget: that field is only
    ever changed by the database trigger when an expense is approved,
    never directly by a client, so there's no field here to bypass it.
    """
    name: str | None = Field(default=None, min_length=1, max_length=100)
    allocated_budget: float | None = Field(default=None, ge=0)
    low_balance_threshold: float | None = Field(default=None, ge=0)


class CategoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    allocated_budget: float
    remaining_budget: float
    low_balance_threshold: float | None
    created_by: uuid.UUID | None
    created_at: datetime
    updated_at: datetime


# ---- Events ---------------------------------------------------------------

EventStatus = Literal["draft", "pending", "approved", "rejected", "completed"]


class EventCreate(BaseModel):
    category_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    event_date: date | None = None
    estimated_cost: float = Field(ge=0, default=0)
    # Officers can save a proposal as a draft first, or submit it for
    # review right away — both are valid starting states, so this is
    # constrained to just those two rather than reusing EventStatus.
    status: Literal["draft", "pending"] = "draft"


class EventUpdate(BaseModel):
    """
    PATCH semantics — only sent fields change. `status` is deliberately
    excluded: moving an event between statuses goes through the
    dedicated /submit, /approve, /reject actions instead of a raw
    PATCH, so the approval workflow can't be bypassed by just setting
    status="approved" here.
    """
    category_id: uuid.UUID | None = None
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    event_date: date | None = None
    estimated_cost: float | None = Field(default=None, ge=0)


class EventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    category_id: uuid.UUID | None
    title: str
    description: str | None
    proposed_by: uuid.UUID
    status: EventStatus
    event_date: date | None
    estimated_cost: float
    created_at: datetime
    updated_at: datetime


class ApprovalDecision(BaseModel):
    """Optional body for POST /events/{id}/approve and /reject."""
    remarks: str | None = None


class ApprovalOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    entity_type: str
    entity_id: uuid.UUID
    step_order: int
    reviewer_id: uuid.UUID | None
    decision: str
    remarks: str | None
    decided_at: datetime | None
    created_at: datetime
