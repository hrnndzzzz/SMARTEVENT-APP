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

EventStatus = Literal["draft", "pending_adviser", "pending_admin", "approved", "rejected", "completed"]


class EventCreate(BaseModel):
    category_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    event_date: date | None = None
    estimated_cost: float = Field(ge=0, default=0)
    # The event's REAL, trackable budget — separate from estimated_cost
    # (which stays a planning figure). Expenses tied to this event draw
    # down remaining_budget, same relationship categories have between
    # allocated_budget and remaining_budget.
    allocated_budget: float = Field(ge=0, default=0)
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
    # remaining_budget is deliberately NOT here — same reasoning as
    # CategoryUpdate: it's only ever changed by the DB trigger
    # (fn_deduct_event_budget) on expense approval, never a direct PATCH.
    allocated_budget: float | None = Field(default=None, ge=0)


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
    allocated_budget: float
    remaining_budget: float
    created_at: datetime
    updated_at: datetime


class ApprovalDecision(BaseModel):
    """Optional body for POST .../approve and .../reject (events or expenses)."""
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


# ---- Expenses ---------------------------------------------------------------

ExpenseStatus = Literal["pending", "approved", "rejected"]


class ExpenseItemInput(BaseModel):
    """
    One line item on an expense, submitted at creation time. Same shape
    as ScannedReceiptItem (see below) on purpose — an officer who used
    scan-receipt can pass its reviewed/corrected items straight through
    here without any reshaping.
    """
    name: str = Field(min_length=1, max_length=150)
    amount: float = Field(gt=0)
    category: Literal["asset", "consumable"]


class ExpenseCreate(BaseModel):
    event_id: uuid.UUID | None = None
    category_id: uuid.UUID
    description: str = Field(min_length=1)
    amount: float = Field(gt=0)
    # Real receipt upload (Supabase Storage) isn't wired up yet — this
    # just accepts a URL string in the meantime, e.g. for testing or a
    # manually-hosted receipt image.
    receipt_url: str | None = None
    # Optional itemized breakdown (typically populated from a prior
    # POST /expenses/scan-receipt call, reviewed/edited by the officer).
    # Only 'asset' items here get converted to inventory on approval —
    # see approve_expense in routers/expenses.py.
    items: list[ExpenseItemInput] = Field(default_factory=list)


class ExpenseUpdate(BaseModel):
    """
    PATCH semantics — only sent fields change. `status` is excluded for
    the same reason as EventUpdate: status changes only happen through
    /approve and /reject, never a raw PATCH — that keeps the
    budget-deduction trigger firing exactly once, from exactly one path.
    OCR fields (`ocr_merchant`, `ocr_date`, `ocr_amount`) and
    `is_flagged`/`flag_reason` aren't editable here either — those are
    meant to be system/OCR-populated once that pipeline exists, not
    something a client sets by hand.
    """
    event_id: uuid.UUID | None = None
    category_id: uuid.UUID | None = None
    description: str | None = Field(default=None, min_length=1)
    amount: float | None = Field(default=None, gt=0)
    receipt_url: str | None = None


class ExpenseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    event_id: uuid.UUID | None
    category_id: uuid.UUID
    description: str
    amount: float
    receipt_url: str | None
    ocr_merchant: str | None
    ocr_date: date | None
    ocr_amount: float | None
    is_flagged: bool
    flag_reason: str | None
    status: ExpenseStatus
    recorded_by: uuid.UUID
    created_at: datetime
    updated_at: datetime


class ExpenseItemOut(BaseModel):
    """Response shape for GET /expenses/{id}/items."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    expense_id: uuid.UUID
    name: str
    amount: float
    category: Literal["asset", "consumable"]
    # Set only for 'asset' items on an APPROVED expense, once
    # approve_expense has converted it into an Inventory row.
    converted_inventory_id: uuid.UUID | None
    created_at: datetime


# ---- Inventory --------------------------------------------------------------

class InventoryCreate(BaseModel):
    item_name: str = Field(min_length=1, max_length=150)
    description: str | None = None
    # Starting stock count — after creation, quantity only moves via
    # POST /inventory/{id}/transactions, same pattern as
    # remaining_budget only moving via expense approval.
    quantity: int = Field(ge=0, default=0)
    unit: str = Field(default="pcs", max_length=30)
    low_stock_threshold: int = Field(ge=0, default=5)
    location: str | None = None


class InventoryUpdate(BaseModel):
    """
    PATCH semantics — only sent fields change. `quantity` is
    deliberately excluded: stock levels only move through
    POST /inventory/{id}/transactions so every change to quantity has
    a matching InventoryTransaction row explaining why.
    """
    item_name: str | None = Field(default=None, min_length=1, max_length=150)
    description: str | None = None
    unit: str | None = Field(default=None, max_length=30)
    low_stock_threshold: int | None = Field(default=None, ge=0)
    location: str | None = None


class InventoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    item_name: str
    description: str | None
    quantity: int
    unit: str
    low_stock_threshold: int
    location: str | None
    is_draft: bool
    created_at: datetime
    updated_at: datetime


class InventoryTransactionCreate(BaseModel):
    # Positive change_qty = stock coming in (purchased, donated,
    # returned). Negative = stock going out (checked out for an event,
    # lost, damaged). Zero isn't a meaningful transaction.
    event_id: uuid.UUID | None = None
    change_qty: int = Field(ne=0)
    reason: str | None = Field(default=None, max_length=100)


class InventoryTransactionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    inventory_id: uuid.UUID
    event_id: uuid.UUID | None
    change_qty: int
    reason: str | None
    performed_by: uuid.UUID
    created_at: datetime


# ---- Receipt OCR ------------------------------------------------------------

class ReceiptParseRequest(BaseModel):
    """
    Body for POST /expenses/{id}/parse-receipt.

    `raw_text` is whatever the Flutter app's on-device OCR (ML Kit)
    extracted from the receipt photo — unstructured text, not a file.
    This endpoint doesn't accept images; the phone does the image-to-text
    step, this API does the text-to-structured-fields step.
    """
    raw_text: str = Field(min_length=1)


class ScannedReceiptItem(BaseModel):
    name: str
    amount: float
    category: Literal["asset", "consumable"]


class ScanReceiptResponse(BaseModel):
    """
    Response for POST /expenses/scan-receipt. Deliberately NOT ExpenseOut
    — no Expense row exists yet at this point. "receipt_url" is filled
    in because the image is uploaded to Storage as part of this same
    call (so the officer's photo isn't lost even if they abandon the
    form afterward), but merchant/date/amount/items are just Gemini's
    read of the receipt for the officer to review and correct in the
    app before calling POST /expenses with the final values.
    """
    receipt_url: str
    merchant: str | None
    date: date | None
    amount: float | None
    items: list[ScannedReceiptItem]


# ---- Analytics / Reports / Recommendations --------------------------------

class DashboardSummary(BaseModel):
    """Response for GET /analytics/dashboard — a single-call overview."""
    total_categories: int
    total_allocated_budget: float
    total_remaining_budget: float
    events_by_status: dict[str, int]
    expenses_by_status: dict[str, int]
    flagged_expense_count: int
    low_stock_item_count: int
    draft_inventory_count: int


class SpendingTrendPoint(BaseModel):
    """One point in GET /analytics/spending-trends — one calendar month."""
    month: str  # "YYYY-MM"
    total_amount: float
    expense_count: int


class CategoryReport(BaseModel):
    """Response for GET /reports/category/{category_id}."""
    category_id: uuid.UUID
    category_name: str
    allocated_budget: float
    remaining_budget: float
    total_spent: float
    approved_expense_count: int
    pending_expense_count: int
    rejected_expense_count: int


class EventReport(BaseModel):
    """
    Response for GET /reports/event/{event_id} — a liquidation-style
    report. Expenses are embedded directly here (unlike the general
    pattern elsewhere of a separate GET .../items endpoint) because a
    report is meant to be one consolidated call, not something the
    client stitches together from several requests.
    """
    event_id: uuid.UUID
    title: str
    status: EventStatus
    estimated_cost: float
    allocated_budget: float
    remaining_budget: float
    total_spent: float
    expenses: list[ExpenseOut]


class BudgetRecommendation(BaseModel):
    """
    Response for GET /recommendations/event-budget?category_id=...

    avg_allocated_budget and avg_actual_spend are deliberately separate
    numbers — what past events PLANNED to spend (allocated_budget) and
    what they ACTUALLY spent (sum of their approved expenses) often
    diverge, and an officer proposing a new event benefits from seeing
    both rather than one blended figure.
    """
    category_id: uuid.UUID
    sample_size: int
    avg_allocated_budget: float | None
    avg_actual_spend: float | None
    note: str
