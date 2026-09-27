"""
Pydantic schemas — these define what JSON goes IN and OUT of the API.
Kept separate from models.py (the DB layer) on purpose: it lets you
return a trimmed-down UserOut (no password_hash!) while User the ORM
model still has that column internally.
"""

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, EmailStr, ConfigDict, Field, HttpUrl, field_validator, model_validator

Money = Annotated[Decimal, Field(gt=0, max_digits=12, decimal_places=2)]
FundSource = Literal["registration_fees", "sponsorship", "donation", "other"]

Role = Literal["super_admin", "admin", "adviser", "officer", "treasurer", "sds_staff"]


# ---- Auth / Users --------------------------------------------------------

class CiteSelfRegisterRequest(BaseModel):
    """
    Body for POST /auth/register. The user supplies their email and chosen
    password. The role and full_name are looked up from the pre-approved
    CiteMember roster entry, preventing arbitrary role self-assignment.
    Account starts inactive/unverified until verified via POST /auth/verify-otp.
    """
    email: EmailStr
    password: str = Field(min_length=8)


class VerifyOtpRequest(BaseModel):
    """Body for POST /auth/verify-otp to verify registration OTP and activate account."""
    email: EmailStr
    otp_code: str = Field(min_length=6, max_length=6)


class AdminRegisterRequest(BaseModel):
    """Body for POST /auth/register/admin — a super_admin creates a department-scoped Admin account."""
    full_name: str = Field(min_length=1, max_length=150)
    email: EmailStr
    organization_id: uuid.UUID
    department_id: uuid.UUID = Field(
        description="Department this Admin will manage. Select an ID from GET /departments."
    )
    position: str | None = None


class SdsRegisterRequest(BaseModel):
    """Body for POST /auth/register/sds — a super_admin creates an SDS account."""
    full_name: str = Field(min_length=1, max_length=150)
    email: EmailStr
    position: str | None = None


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8)


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    otp_code: str = Field(min_length=6, max_length=6)
    new_password: str = Field(min_length=8)


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
    department_id: uuid.UUID | None
    organization_id: uuid.UUID | None = None
    is_active: bool
    is_suspended: bool = False
    must_change_password: bool
    created_at: datetime


class DepartmentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    code: str
    name: str
    description: str | None
    created_at: datetime


class UserDepartmentUpdate(BaseModel):
    department_id: uuid.UUID
    organization_id: uuid.UUID


class OrganizationCreate(BaseModel):
    code: str = Field(min_length=1, max_length=30)
    name: str = Field(min_length=1, max_length=150)
    department_id: uuid.UUID


class DepartmentCreate(BaseModel):
    code: str = Field(min_length=1, max_length=20)
    name: str = Field(min_length=1, max_length=150)
    description: str | None = None


class OrganizationOut(OrganizationCreate):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    created_at: datetime


class UserAccessUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: Literal["admin", "adviser", "treasurer", "officer", "sds_staff"] | None = None
    organization_id: uuid.UUID | None = None
    position: str | None = Field(default=None, max_length=50)
    is_suspended: bool | None = None


class AuditLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    user_id: uuid.UUID | None
    organization_id: uuid.UUID | None
    department_id: uuid.UUID | None
    action: str
    entity_type: str | None
    entity_id: uuid.UUID | None
    details: dict | None
    created_at: datetime


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class TokenData(BaseModel):
    user_id: str | None = None


# ---- Categories -----------------------------------------------------------

class CategoryCreate(BaseModel):
    organization_id: uuid.UUID | None = None
    name: str = Field(min_length=1, max_length=100)
    department_id: uuid.UUID | None = None
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
    department_id: uuid.UUID | None = None
    allocated_budget: float | None = Field(default=None, ge=0)
    low_balance_threshold: float | None = Field(default=None, ge=0)


class CategoryOut(BaseModel):
    organization_id: uuid.UUID | None = None
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    department_id: uuid.UUID | None
    name: str
    allocated_budget: float
    remaining_budget: float
    low_balance_threshold: float | None
    created_by: uuid.UUID | None
    created_at: datetime
    updated_at: datetime


# ---- Events ---------------------------------------------------------------

EventStatus = Literal[
    "draft",
    "pending",
    "pending_adviser",
    "pending_admin",
    "approved",
    "rejected",
    "completed",
]
Semester = Literal["1st", "2nd", "summer"]
EventScope = Literal["departmental", "organizational"]


class EventCreate(BaseModel):
    @field_validator("school_year")
    @classmethod
    def valid_school_year(cls, value):
        from app.services.academic_year import validate_school_year
        return validate_school_year(value)

    organization_id: uuid.UUID | None = None
    category_id: uuid.UUID | None = None
    department_id: uuid.UUID | None = None
    school_year: str = Field(
        ...,
        min_length=9,
        max_length=9,
        pattern=r"^\d{4}-\d{4}$",
        description='Academic year format: "2025-2026"',
    )
    semester: Semester
    event_scope: EventScope
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    event_date: date | None = None
    estimated_cost: float = Field(ge=0, default=0)
    # The event's REAL, trackable budget — separate from estimated_cost
    # (which stays a planning figure). Expenses tied to this event draw
    # down remaining_budget, same relationship categories have between
    # allocated_budget and remaining_budget.
    allocated_budget: float = Field(ge=0, default=0)
    # Authorized writers can save a proposal as a draft first, or submit it for
    # review right away — both are valid starting states, so this is
    # constrained to just those two rather than reusing EventStatus.
    status: Literal["draft", "pending"] = "draft"


class EventUpdate(BaseModel):
    @field_validator("school_year", "semester", "event_scope")
    @classmethod
    def academic_metadata_cannot_be_cleared(cls, value, info):
        if value is None:
            raise ValueError(f"{info.field_name} cannot be null")
        if info.field_name == "school_year":
            from app.services.academic_year import validate_school_year
            return validate_school_year(value)
        return value

    """
    PATCH semantics — only sent fields change. `status` is deliberately
    excluded: moving an event between statuses goes through the
    dedicated /submit, /approve, /reject actions instead of a raw
    PATCH, so the approval workflow can't be bypassed by just setting
    status="approved" here.
    """
    category_id: uuid.UUID | None = None
    department_id: uuid.UUID | None = None
    school_year: str | None = Field(
        default=None,
        min_length=9,
        max_length=9,
        pattern=r"^\d{4}-\d{4}$",
    )
    semester: Semester | None = None
    event_scope: EventScope | None = None
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    event_date: date | None = None
    estimated_cost: float | None = Field(default=None, ge=0)
    # remaining_budget is deliberately NOT here — same reasoning as
    # CategoryUpdate: it's only ever changed by the DB trigger
    # (fn_deduct_event_budget) on expense approval, never a direct PATCH.
    allocated_budget: float | None = Field(default=None, ge=0)


class EventAcademicMetadata(BaseModel):
    model_config = ConfigDict(extra="forbid")
    school_year: str
    semester: Semester
    event_scope: EventScope

    @field_validator("school_year")
    @classmethod
    def valid_school_year(cls, value):
        from app.services.academic_year import validate_school_year
        return validate_school_year(value)


class RegistrationVerificationOut(BaseModel):
    detail: str
    registration_status: Literal["approved"] = "approved"
    notification_id: uuid.UUID | None = None
    confirmation_email_status: Literal["pending", "sent", "failed"] | None = None


class NotificationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    kind: str
    title: str
    body: str
    read_at: datetime | None
    email_status: Literal["pending", "sent", "failed"]
    created_at: datetime


class EventOut(BaseModel):
    organization_id: uuid.UUID | None = None
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    department_id: uuid.UUID | None
    category_id: uuid.UUID | None
    # Optional only while legacy rows are being backfilled. New API-created
    # events always contain these values.
    school_year: str | None
    semester: Semester | None
    event_scope: EventScope | None
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
    quantity: int = Field(default=1, gt=0)
    unit: str = Field(default="pcs", min_length=1, max_length=30)
    """
    One line item on an expense, submitted at creation time. Same shape
    as ScannedReceiptItem (see below) on purpose — an officer who used
    scan-receipt can pass its reviewed/corrected items straight through
    here without any reshaping.
    """
    name: str = Field(min_length=1, max_length=150)
    amount: Money
    category: Literal["asset", "consumable"]


class ReceiptDetails(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    receipt_url: HttpUrl
    purpose: str = Field(min_length=1, max_length=2000)
    merchant: str | None = Field(default=None, min_length=1, max_length=150)
    receipt_number: str | None = Field(default=None, min_length=1, max_length=100)
    issued_on: date | None = None
    amount: Money | None = None


class ReceiptCreate(ReceiptDetails):
    expense_id: uuid.UUID | None = None
    income_id: uuid.UUID | None = None

    @model_validator(mode="after")
    def one_transaction(self):
        if (self.expense_id is None) == (self.income_id is None):
            raise ValueError("Provide exactly one expense_id or income_id")
        return self


class ReceiptOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    organization_id: uuid.UUID
    department_id: uuid.UUID
    event_id: uuid.UUID
    expense_id: uuid.UUID | None
    income_id: uuid.UUID | None
    purpose: str
    receipt_url: str
    merchant: str | None
    receipt_number: str | None
    issued_on: date
    amount: float
    is_flagged: bool
    similar_receipt_ids: list[uuid.UUID]
    review_status: Literal["clear", "pending", "cleared", "rejected"]
    review_reason: str | None
    reviewed_by: uuid.UUID | None
    reviewed_at: datetime | None
    recorded_by: uuid.UUID
    created_at: datetime


class ReceiptReview(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    reason: str = Field(min_length=10, max_length=2000)
    decision: Literal["cleared", "rejected"] = "cleared"


class ExpenseCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    organization_id: uuid.UUID | None = None
    event_id: uuid.UUID | None = None
    category_id: uuid.UUID
    department_id: uuid.UUID | None = None
    description: str = Field(min_length=1)
    amount: Money
    expense_date: date = Field(default_factory=date.today)
    # Real receipt upload (Supabase Storage) isn't wired up yet — this
    # just accepts a URL string in the meantime, e.g. for testing or a
    # manually-hosted receipt image.
    receipt_url: HttpUrl | None = None
    receipt: ReceiptDetails | None = None
    # Optional itemized breakdown (typically populated from a prior
    # POST /expenses/scan-receipt call, reviewed/edited by the officer).
    # Only asset items enter stock, after approved expenses are paid and
    # received through POST /expenses/{id}/complete-purchase.
    items: list[ExpenseItemInput] = Field(default_factory=list)

    @model_validator(mode="after")
    def itemized_total_cannot_exceed_expense(self):
        if sum((item.amount for item in self.items), Decimal("0.00")) > self.amount:
            raise ValueError("Itemized line amounts cannot exceed the expense total")
        return self


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
    department_id: uuid.UUID | None = None
    description: str | None = Field(default=None, min_length=1)
    amount: Money | None = None
    expense_date: date | None = None
    receipt_url: HttpUrl | None = None

    @field_validator("event_id", "category_id", "description", "amount", "expense_date")
    @classmethod
    def cannot_clear_required_transaction_fields(cls, value):
        if value is None:
            raise ValueError("Transaction fields cannot be cleared")
        if isinstance(value, str) and not value.strip():
            raise ValueError("Description cannot be blank")
        return value.strip() if isinstance(value, str) else value


class ExpenseOut(BaseModel):
    purchase_completed_at: datetime | None = None
    paid_on: date | None = None
    received_on: date | None = None
    payment_method: str | None = None
    payment_reference: str | None = None
    purchase_vendor: str | None = None
    paid_amount: float | None = None
    organization_id: uuid.UUID | None = None
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    department_id: uuid.UUID | None
    event_id: uuid.UUID | None
    category_id: uuid.UUID
    description: str
    amount: float
    expense_date: date
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


class IncomeCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    event_id: uuid.UUID
    source: str = Field(min_length=1, max_length=100)
    source_type: FundSource = "other"
    purpose: str = Field(min_length=1)
    amount: Money
    received_on: date = Field(default_factory=date.today)
    receipt: ReceiptDetails | None = None


class IncomeOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    event_id: uuid.UUID
    source: str
    source_type: FundSource = "other"
    receipt_review_status: Literal["clear", "pending", "cleared", "rejected"] = "clear"
    purpose: str
    amount: float
    received_on: date
    recorded_by: uuid.UUID
    created_at: datetime


class ExpenseItemOut(BaseModel):
    quantity: int = 1
    unit: str = "pcs"
    """Response shape for GET /expenses/{id}/items."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    expense_id: uuid.UUID
    name: str
    amount: float
    category: Literal["asset", "consumable"]
    # Set for asset items after documented purchase completion.
    converted_inventory_id: uuid.UUID | None
    created_at: datetime


# ---- Inventory --------------------------------------------------------------

InventoryTransactionType = Literal["opening_balance", "acquisition", "donation", "purchase", "issue", "return", "disposal", "adjustment", "legacy"]


class PurchaseItemConfirmation(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    expense_item_id: uuid.UUID
    quantity: int = Field(gt=0)
    unit: str = Field(min_length=1, max_length=30)


class PurchaseCompletion(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    paid_on: date
    received_on: date
    paid_amount: Money
    payment_method: Literal["cash", "bank_transfer", "card", "other"]
    payment_reference: str = Field(min_length=1, max_length=150)
    vendor: str = Field(min_length=1, max_length=150)
    items: list[PurchaseItemConfirmation] = Field(min_length=1)

    @field_validator("paid_on", "received_on")
    @classmethod
    def dates_cannot_be_future(cls, value):
        if value > date.today():
            raise ValueError("Completed payment/delivery dates cannot be in the future")
        return value


class InventoryCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    event_id: uuid.UUID
    initial_transaction_type: Literal["opening_balance", "acquisition", "donation"] = "opening_balance"
    reason: str = Field(default="Opening stock", min_length=1, max_length=100)
    organization_id: uuid.UUID | None = None
    item_name: str = Field(min_length=1, max_length=150)
    department_id: uuid.UUID | None = None
    description: str | None = None
    # Starting stock count — after creation, quantity only moves via
    # POST /inventory/{id}/transactions, same pattern as
    # remaining_budget only moving via expense approval.
    quantity: int = Field(ge=0, default=0)
    unit: str = Field(default="pcs", min_length=1, max_length=30)
    low_stock_threshold: int = Field(ge=0, default=5)
    location: str | None = None


class InventoryUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    event_id: uuid.UUID | None = None

    @field_validator("event_id", "item_name", "unit", "low_stock_threshold")
    @classmethod
    def required_values_cannot_be_cleared(cls, value):
        if value is None or (isinstance(value, str) and not value.strip()):
            raise ValueError("Inventory fields cannot be cleared")
        return value.strip() if isinstance(value, str) else value
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
    event_id: uuid.UUID | None = None
    organization_id: uuid.UUID | None = None
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    department_id: uuid.UUID | None
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
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    transaction_type: Literal["acquisition", "donation", "purchase", "issue", "return", "disposal", "adjustment"]
    # Positive change_qty = stock coming in (purchased, donated,
    # returned). Negative = stock going out (checked out for an event,
    # lost, damaged). Zero isn't a meaningful transaction.
    event_id: uuid.UUID
    change_qty: int
    reason: str = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def transaction_direction(self):
        if self.transaction_type in {"acquisition", "donation", "purchase", "return"} and self.change_qty <= 0:
            raise ValueError("Incoming transactions require positive change_qty")
        if self.transaction_type in {"issue", "disposal"} and self.change_qty >= 0:
            raise ValueError("Outgoing transactions require negative change_qty")
        return self

    @field_validator("change_qty")
    @classmethod
    def change_qty_must_not_be_zero(cls, value: int) -> int:
        if value == 0:
            raise ValueError("change_qty must not be zero")
        return value


class InventoryTransactionRepair(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    event_id: uuid.UUID
    transaction_type: Literal["opening_balance", "acquisition", "donation", "issue", "return", "disposal", "adjustment"]
    reason: str = Field(min_length=1, max_length=100)


class InventoryTransactionOut(BaseModel):
    transaction_type: InventoryTransactionType = "legacy"
    expense_item_id: uuid.UUID | None = None
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


class IncomeSourceSummary(BaseModel):
    source_type: FundSource
    source: str
    income_count: int
    total_income: float


class EventReport(BaseModel):
    """
    Response for GET /reports/event/{event_id} — a liquidation-style
    report. Expenses are embedded directly here (unlike the general
    pattern elsewhere of a separate GET .../items endpoint) because a
    report is meant to be one consolidated call, not something the
    client stitches together from several requests.
    """
    event_id: uuid.UUID
    school_year: str | None = None
    semester: Semester | None = None
    event_scope: EventScope | None = None
    title: str
    status: EventStatus
    estimated_cost: float
    allocated_budget: float
    remaining_budget: float
    total_income: float
    total_spent: float
    net_balance: float
    income_by_source: list[IncomeSourceSummary] = Field(default_factory=list)
    withheld_income_total: float = 0
    withheld_income_count: int = 0
    receipts: list[ReceiptOut] = Field(default_factory=list)
    incomes: list[IncomeOut]
    expenses: list[ExpenseOut]


class FinancialEventSummary(BaseModel):
    event_id: uuid.UUID
    title: str
    school_year: str | None
    semester: Semester | None
    event_scope: EventScope | None
    income_count: int
    expense_count: int
    total_income: float
    total_expenses: float
    net_balance: float
    withheld_income_total: float = 0
    withheld_income_count: int = 0


class ConsolidatedFinancialReport(BaseModel):
    period: Literal["weekly", "monthly", "school_year", "semester"]
    start_date: date | None
    end_date: date | None
    school_year: str | None
    semester: Semester | None
    event_scope: EventScope | None
    total_income: float
    total_expenses: float
    unassigned_expense_total: float
    net_balance: float
    events: list[FinancialEventSummary]
    income_by_source: list[IncomeSourceSummary] = Field(default_factory=list)
    withheld_income_total: float = 0
    withheld_income_count: int = 0


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


# ---- CITE Member Roster ---------------------------------------------------

class CiteMemberCreate(BaseModel):
    organization_id: uuid.UUID | None = None
    full_name: str = Field(min_length=1, max_length=150)
    email: EmailStr
    role: Literal["officer", "adviser", "treasurer"]
    position: str | None = None
    department_id: uuid.UUID | None = Field(
        default=None,
        description="Admins may omit this to use their assigned department. Super_Admin must select a department from GET /departments.",
    )


class CiteMemberOut(BaseModel):
    organization_id: uuid.UUID | None = None
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    email: EmailStr
    role: Literal["officer", "adviser", "treasurer"]
    position: str | None
    department_id: uuid.UUID | None
    claimed_by_user_id: uuid.UUID | None
    created_at: datetime


class CiteMemberUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: Literal["officer", "adviser", "treasurer"] | None = None
    position: str | None = Field(default=None, max_length=50)
    organization_id: uuid.UUID | None = None


# ---- Event Proposal Letters -------------------------------------------------

class EventProposalLetterOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    event_id: uuid.UUID
    title: str
    document_url: str
    submitted_by: uuid.UUID
    created_at: datetime
