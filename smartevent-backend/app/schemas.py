import uuid
from datetime import date, datetime, time
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, EmailStr, ConfigDict, Field, HttpUrl, field_validator, model_validator

from app.services.academic_year import institution_today

AccountEmail = Annotated[EmailStr, Field(max_length=150), AfterValidator(str.lower)]

Money = Annotated[Decimal, Field(gt=0, max_digits=12, decimal_places=2)]
NonnegativeMoney = Annotated[Decimal, Field(ge=0, max_digits=12, decimal_places=2)]
FundSource = Literal["registration_fees", "sponsorship", "donation", "other"]

Role = Literal["super_admin", "admin", "adviser", "officer", "treasurer", "sds_staff", "signatory"]


class CiteSelfRegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: AccountEmail
    password: str = Field(min_length=8, max_length=128)


class VerifyOtpRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    email: AccountEmail
    otp_code: str = Field(pattern=r"^[0-9]{6}$")


class AdminRegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    full_name: str = Field(min_length=1, max_length=150)
    email: AccountEmail
    organization_id: uuid.UUID
    department_id: uuid.UUID = Field(
        description="Department this Admin will manage. Select an ID from GET /departments."
    )
    position: str | None = Field(default=None, max_length=50)


class SdsRegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    full_name: str = Field(min_length=1, max_length=150)
    email: AccountEmail
    position: str | None = Field(default=None, max_length=50)


class SignatoryRegisterRequest(SdsRegisterRequest):
    pass


class SignatoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    full_name: str
    position: str | None


class ChangePasswordRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class ForgotPasswordRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    email: AccountEmail


class ResetPasswordRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: AccountEmail
    otp_code: str = Field(pattern=r"^[0-9]{6}$")
    new_password: str = Field(min_length=8, max_length=128)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    email: EmailStr
    role: Role
    position: str | None
    department_id: uuid.UUID | None
    organization_id: uuid.UUID | None = None
    organization_name: str | None = None
    department_name: str | None = None
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
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    department_id: uuid.UUID
    organization_id: uuid.UUID


class OrganizationCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    code: str = Field(min_length=1, max_length=30)
    name: str = Field(min_length=1, max_length=150)
    department_id: uuid.UUID


class DepartmentCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    code: str = Field(min_length=1, max_length=20)
    name: str = Field(min_length=1, max_length=150)
    description: str | None = Field(default=None, max_length=10000)


class OrganizationOut(OrganizationCreate):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    created_at: datetime


class UserAccessUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    role: Literal["admin", "adviser", "treasurer", "officer", "sds_staff", "signatory"] | None = None
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
    must_change_password: bool = False


class CategoryCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    organization_id: uuid.UUID | None = None
    name: str = Field(min_length=1, max_length=100)
    department_id: uuid.UUID | None = None
    allocated_budget: NonnegativeMoney = Decimal("0.00")
    low_balance_threshold: NonnegativeMoney = Decimal("0.00")


class CategoryUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    @field_validator("name", "allocated_budget", "low_balance_threshold")
    @classmethod
    def cannot_clear_category_fields(cls, value):
        if value is None:
            raise ValueError("Category fields cannot be null")
        return value

    name: str | None = Field(default=None, min_length=1, max_length=100)
    department_id: uuid.UUID | None = None
    allocated_budget: NonnegativeMoney | None = Field(default=None, ge=0)
    low_balance_threshold: NonnegativeMoney | None = Field(default=None, ge=0)


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


EventStatus = Literal[
    "draft",
    "pending",
    "pending_adviser",
    "pending_admin",
    "pending_institutional_review",
    "approved",
    "rejected",
    "completed",
]
Semester = Literal["1st", "2nd", "summer"]
EventScope = Literal["departmental", "organizational"]


class EventCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
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
    description: str | None = Field(default=None, max_length=10000)
    event_date: date | None = None
    estimated_cost: NonnegativeMoney = Decimal("0.00")


    allocated_budget: NonnegativeMoney = Decimal("0.00")


    status: Literal["draft", "pending"] = "draft"


class EventUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    @field_validator("school_year", "semester", "event_scope", "title", "estimated_cost", "allocated_budget")
    @classmethod
    def academic_metadata_cannot_be_cleared(cls, value, info):
        if value is None:
            raise ValueError(f"{info.field_name} cannot be null")
        if info.field_name == "school_year":
            from app.services.academic_year import validate_school_year
            return validate_school_year(value)
        return value

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
    description: str | None = Field(default=None, max_length=10000)
    event_date: date | None = None
    estimated_cost: NonnegativeMoney | None = Field(default=None, ge=0)


    allocated_budget: NonnegativeMoney | None = Field(default=None, ge=0)


class EventAcademicMetadata(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
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
    payload: dict[str, str | int] | None = None
    read_at: datetime | None
    email_status: Literal["pending", "sent", "failed"]
    created_at: datetime


class EventOut(BaseModel):
    organization_id: uuid.UUID | None = None
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    department_id: uuid.UUID | None
    category_id: uuid.UUID | None


    school_year: str | None
    semester: Semester | None
    event_scope: EventScope | None
    title: str
    description: str | None
    proposed_by: uuid.UUID
    status: EventStatus
    review_round: int = 1
    completed_on: date | None = None
    completed_at: datetime | None = None
    completed_by: uuid.UUID | None = None
    event_date: date | None
    start_time: time | None = None
    end_time: time | None = None
    estimated_cost: float
    allocated_budget: float
    remaining_budget: float
    created_at: datetime
    updated_at: datetime


class ApprovalDecision(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    remarks: str | None = Field(default=None, max_length=2000)
    expected_version: int | None = Field(
        default=None,
        ge=1,
        description="SAP proposals only: the proposal version last read; a proposal that has changed since answers 409. Other events and expenses ignore it.",
    )


class DocumentRoutingUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    signatory_ids: list[uuid.UUID] = Field(min_length=1, max_length=20)

    @field_validator("signatory_ids")
    @classmethod
    def unique_signatories(cls, value):
        if len(value) != len(set(value)):
            raise ValueError("Assign each signatory only once per review round")
        return value


class DocumentRoutingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    event_id: uuid.UUID
    review_round: int
    step_order: int
    signatory_id: uuid.UUID
    status: Literal["pending", "approved", "rejected"]
    remarks: str | None
    decided_at: datetime | None
    created_at: datetime


class RequirementPresetOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    code: str
    name: str
    description: str | None
    phase: Literal["pre_activity", "post_activity"]
    requires_notarization: bool
    is_sensitive: bool


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


ExpenseStatus = Literal["pending", "approved", "rejected"]


class ExpenseItemInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    quantity: int = Field(default=1, gt=0, le=2147483647)
    unit: str = Field(default="pcs", min_length=1, max_length=30)
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
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
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
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    organization_id: uuid.UUID | None = None
    event_id: uuid.UUID | None = None
    category_id: uuid.UUID
    department_id: uuid.UUID | None = None
    description: str = Field(min_length=1, max_length=10000)
    amount: Money
    expense_date: date = Field(default_factory=institution_today)


    receipt_url: HttpUrl | None = None
    receipt: ReceiptDetails | None = None


    items: list[ExpenseItemInput] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def itemized_total_cannot_exceed_expense(self):
        if sum((item.amount for item in self.items), Decimal("0.00")) > self.amount:
            raise ValueError("Itemized line amounts cannot exceed the expense total")
        return self


class ExpenseUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    event_id: uuid.UUID | None = None
    category_id: uuid.UUID | None = None
    department_id: uuid.UUID | None = None
    description: str | None = Field(default=None, min_length=1, max_length=10000)
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
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    event_id: uuid.UUID
    source: str = Field(min_length=1, max_length=100)
    source_type: FundSource = "other"
    purpose: str = Field(min_length=1, max_length=2000)
    amount: Money
    received_on: date = Field(default_factory=institution_today)
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
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    expense_id: uuid.UUID
    name: str
    amount: float
    category: Literal["asset", "consumable"]

    converted_inventory_id: uuid.UUID | None
    created_at: datetime


InventoryTransactionType = Literal["opening_balance", "acquisition", "donation", "purchase", "issue", "return", "disposal", "adjustment", "legacy"]


class PurchaseItemConfirmation(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    expense_item_id: uuid.UUID
    quantity: int = Field(gt=0, le=2147483647)
    unit: str = Field(min_length=1, max_length=30)


class PurchaseCompletion(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    paid_on: date
    received_on: date
    paid_amount: Money
    payment_method: Literal["cash", "bank_transfer", "card", "other"]
    payment_reference: str = Field(min_length=1, max_length=150)
    vendor: str = Field(min_length=1, max_length=150)
    items: list[PurchaseItemConfirmation] = Field(min_length=1, max_length=100)

    @field_validator("paid_on", "received_on")
    @classmethod
    def dates_cannot_be_future(cls, value):
        if value > institution_today():
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
    description: str | None = Field(default=None, max_length=10000)


    quantity: int = Field(ge=0, le=2147483647, default=0)
    unit: str = Field(default="pcs", min_length=1, max_length=30)
    low_stock_threshold: int = Field(ge=0, le=2147483647, default=5)
    location: str | None = Field(default=None, max_length=100)


class InventoryUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    event_id: uuid.UUID | None = None

    @field_validator("event_id", "item_name", "unit", "low_stock_threshold")
    @classmethod
    def required_values_cannot_be_cleared(cls, value):
        if value is None or (isinstance(value, str) and not value.strip()):
            raise ValueError("Inventory fields cannot be cleared")
        return value.strip() if isinstance(value, str) else value
    item_name: str | None = Field(default=None, min_length=1, max_length=150)
    description: str | None = Field(default=None, max_length=10000)
    unit: str | None = Field(default=None, max_length=30)
    low_stock_threshold: int | None = Field(default=None, ge=0, le=2147483647)
    location: str | None = Field(default=None, max_length=100)


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


    event_id: uuid.UUID
    change_qty: int = Field(ge=-2147483647, le=2147483647)
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


class ReceiptParseRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    raw_text: str = Field(min_length=1, max_length=50000)


class ScannedReceiptItem(BaseModel):
    name: str
    amount: float
    category: Literal["asset", "consumable"]


class ScanReceiptResponse(BaseModel):
    receipt_url: str
    merchant: str | None
    date: date | None
    amount: float | None
    items: list[ScannedReceiptItem]


class DashboardSummary(BaseModel):
    total_categories: int
    total_allocated_budget: float
    total_remaining_budget: float
    events_by_status: dict[str, int]
    expenses_by_status: dict[str, int]
    flagged_expense_count: int
    low_stock_item_count: int
    draft_inventory_count: int


class SpendingTrendPoint(BaseModel):
    month: str
    total_amount: float
    expense_count: int


class CategoryReport(BaseModel):
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
    category_id: uuid.UUID
    sample_size: int
    avg_allocated_budget: float | None
    avg_actual_spend: float | None
    note: str


class CiteMemberCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    organization_id: uuid.UUID | None = None
    full_name: str = Field(min_length=1, max_length=150)
    email: AccountEmail
    role: Literal["officer", "adviser", "treasurer"]
    position: str | None = Field(default=None, max_length=50)
    department_id: uuid.UUID | None = Field(
        default=None,
        description="Admins may omit this to use their assigned department. Super_Admin must select a department from GET /departments.",
    )


class RosterImportError(BaseModel):
    row: int
    column: str
    message: str


class RosterImportedMember(BaseModel):
    id: uuid.UUID
    email: EmailStr


class RosterImportOut(BaseModel):
    filename: str
    inserted_count: int
    members: list[RosterImportedMember]


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
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    role: Literal["officer", "adviser", "treasurer"] | None = None
    position: str | None = Field(default=None, max_length=50)
    organization_id: uuid.UUID | None = None


class EventProposalLetterOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    event_id: uuid.UUID
    title: str
    document_url: str
    submitted_by: uuid.UUID
    created_at: datetime
