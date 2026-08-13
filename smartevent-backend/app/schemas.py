"""
Pydantic schemas — these define what JSON goes IN and OUT of the API.
Kept separate from models.py (the DB layer) on purpose: it lets you
return a trimmed-down UserOut (no password_hash!) while User the ORM
model still has that column internally.
"""

import uuid
from datetime import datetime
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
