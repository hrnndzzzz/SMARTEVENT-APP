"""
SQLAlchemy ORM models mapping to the tables already created in Supabase
via smartevent_schema.sql. These do NOT create tables (no
Base.metadata.create_all() is called anywhere) — the SQL file is the
source of truth for schema; these classes just let FastAPI query it.

Operational records carry explicit department and organization ownership.
Apply the SQL migrations in scripts/ before deploying model changes.
"""

import uuid

from sqlalchemy import (
    Boolean, CheckConstraint, Column, Date, DateTime, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint, func,
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship, declared_attr

from app.database import Base


class Department(Base):
    """
    School departments — seeded once via scripts/seed_initial_data.py,
    managed by Super Admin through the API. Used to scope operational access
    to their own department's records (see enforce_department_scope in
    dependencies.py), and to tag CiteMember roster entries and Users.
    """
    __tablename__ = "departments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    code = Column(String(20), nullable=False, unique=True)   # e.g. 'SDS', 'CBA', 'CEA', 'SCS'
    name = Column(String(150), nullable=False)               # e.g. 'Student Development Services'
    description = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Organization(Base):
    __tablename__ = "organizations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=False)
    code = Column(String(30), nullable=False, unique=True)
    name = Column(String(150), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class OrganizationScoped:
    @declared_attr
    def organization_id(cls):
        return Column(UUID(as_uuid=True), ForeignKey("organizations.id"), nullable=True)


class User(OrganizationScoped, Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    full_name = Column(String(150), nullable=False)
    email = Column(String(150), nullable=False, unique=True)
    password_hash = Column(Text, nullable=False)
    role = Column(String(20), nullable=False)  # 'super_admin' | 'admin' | 'adviser' | 'officer' | 'treasurer' | 'sds_staff'
    position = Column(String(50), nullable=True)
    # Nullable for Super Admin and SDS; other roles require both assignments.
    # Set automatically from the CiteMember roster entry at registration.
    # Used by enforce_department_scope in dependencies.py.
    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    is_suspended = Column(Boolean, nullable=False, default=False)
    # True immediately after account creation (the password_hash above
    # is an OTP emailed to the user, not a real password they chose).
    # Flipped to False by POST /auth/change-password. See
    # app/services/account_provisioning.py for the creation flow.
    must_change_password = Column(Boolean, nullable=False, default=False)
    fcm_token = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now())

    department = relationship("Department")


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (UniqueConstraint("user_id", "kind", name="uq_notification_user_kind"),)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    kind = Column(String(50), nullable=False)
    title = Column(String(200), nullable=False)
    body = Column(Text, nullable=False)
    read_at = Column(DateTime(timezone=True), nullable=True)
    email_status = Column(String(20), nullable=False, default="pending")
    email_attempts = Column(Integer, nullable=False, default=0)
    email_sent_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class Category(OrganizationScoped, Base):
    __tablename__ = "categories"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=True)
    name = Column(String(100), nullable=False)
    allocated_budget = Column(Numeric(12, 2), nullable=False, default=0)
    remaining_budget = Column(Numeric(12, 2), nullable=False, default=0)
    low_balance_threshold = Column(Numeric(12, 2), default=0)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now())


class Event(OrganizationScoped, Base):
    __tablename__ = "events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=True)
    category_id = Column(UUID(as_uuid=True), ForeignKey("categories.id"), nullable=True)
    # These are nullable during the transition so existing events can be
    # migrated safely. New events are required to provide all three values
    # by EventCreate; a later hardening migration can make them NOT NULL
    # after existing rows have been backfilled.
    school_year = Column(String(9), nullable=True)  # e.g. "2025-2026"
    semester = Column(String(10), nullable=True)  # "1st" | "2nd" | "summer"
    event_scope = Column(String(20), nullable=True)  # "departmental" | "organizational"
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    proposed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    status = Column(String(20), nullable=False, default="draft")
    event_date = Column(Date, nullable=True)
    estimated_cost = Column(Numeric(12, 2), default=0)
    allocated_budget = Column(Numeric(12, 2), nullable=False, default=0)
    remaining_budget = Column(Numeric(12, 2), nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now())

    category = relationship("Category")


class Approval(Base):
    __tablename__ = "approvals"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    entity_type = Column(String(20), nullable=False)  # 'event' | 'expense'
    entity_id = Column(UUID(as_uuid=True), nullable=False)
    step_order = Column(Numeric, nullable=False)
    reviewer_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    decision = Column(String(20), nullable=False, default="pending")
    remarks = Column(Text, nullable=True)
    decided_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Expense(OrganizationScoped, Base):
    __tablename__ = "expenses"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=True)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=True)
    category_id = Column(UUID(as_uuid=True), ForeignKey("categories.id"), nullable=False)
    description = Column(Text, nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    expense_date = Column(Date, nullable=False, server_default=func.current_date())
    receipt_url = Column(Text, nullable=True)
    ocr_merchant = Column(String(150), nullable=True)
    ocr_date = Column(Date, nullable=True)
    ocr_amount = Column(Numeric(12, 2), nullable=True)
    is_flagged = Column(Boolean, nullable=False, default=False)
    flag_reason = Column(Text, nullable=True)
    status = Column(String(20), nullable=False, default="pending")
    purchase_completed_at = Column(DateTime(timezone=True), nullable=True)
    paid_on = Column(Date, nullable=True)
    received_on = Column(Date, nullable=True)
    payment_method = Column(String(30), nullable=True)
    payment_reference = Column(String(150), nullable=True)
    purchase_vendor = Column(String(150), nullable=True)
    paid_amount = Column(Numeric(12, 2), nullable=True)
    recorded_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now())


class IncomeRecord(Base):
    __tablename__ = "income_records"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False)
    source = Column(String(100), nullable=False)
    source_type = Column(String(30), nullable=False, default="other", server_default="other")
    purpose = Column(Text, nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    received_on = Column(Date, nullable=False)
    recorded_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    receipt = relationship("Receipt", foreign_keys="Receipt.income_id", uselist=False)

    @property
    def receipt_review_status(self):
        return self.receipt.review_status if self.receipt else "clear"


class Receipt(OrganizationScoped, Base):
    __tablename__ = "receipts"
    __table_args__ = (
        CheckConstraint("(expense_id IS NOT NULL AND income_id IS NULL) OR (income_id IS NOT NULL AND expense_id IS NULL)", name="receipt_one_transaction"),
        UniqueConstraint("expense_id", name="uq_receipt_expense"),
        UniqueConstraint("income_id", name="uq_receipt_income"),
        UniqueConstraint("organization_id", "url_fingerprint", name="uq_receipt_url"),
        UniqueConstraint("organization_id", "file_sha256", name="uq_receipt_file"),
        UniqueConstraint("organization_id", "reference_key", name="uq_receipt_reference"),
    )
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=False)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False)
    expense_id = Column(UUID(as_uuid=True), ForeignKey("expenses.id"), nullable=True)
    income_id = Column(UUID(as_uuid=True), ForeignKey("income_records.id"), nullable=True)
    purpose = Column(Text, nullable=False)
    receipt_url = Column(Text, nullable=False)
    merchant = Column(String(150), nullable=True)
    receipt_number = Column(String(100), nullable=True)
    issued_on = Column(Date, nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    url_fingerprint = Column(String(64), nullable=False)
    file_sha256 = Column(String(64), nullable=True)
    reference_key = Column(String(64), nullable=True)
    is_flagged = Column(Boolean, nullable=False, default=False)
    similar_receipt_ids = Column(JSONB, nullable=False, default=list)
    review_status = Column(String(20), nullable=False, default="clear")
    review_reason = Column(Text, nullable=True)
    reviewed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
    recorded_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class Inventory(OrganizationScoped, Base):
    __tablename__ = "inventory"
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=True)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=True)
    item_name = Column(String(150), nullable=False)
    description = Column(Text, nullable=True)
    quantity = Column(Numeric, nullable=False, default=0)
    unit = Column(String(30), default="pcs")
    low_stock_threshold = Column(Numeric, nullable=False, default=5)
    location = Column(String(100), nullable=True)
    # True for new catalog items received by complete-purchase from an
    # asset line — stock exists, but the catalog still needs admin review.
    # False for everything created directly through POST /inventory,
    # and flipped to False by POST /inventory/{id}/confirm-draft.
    is_draft = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now())


class ExpenseItem(Base):
    __tablename__ = "expense_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    expense_id = Column(UUID(as_uuid=True), ForeignKey("expenses.id"), nullable=False)
    name = Column(String(150), nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    category = Column(String(20), nullable=False)  # 'asset' | 'consumable'
    quantity = Column(Integer, nullable=False, default=1, server_default="1")
    unit = Column(String(30), nullable=False, default="pcs", server_default="pcs")
    # Set on documented purchase completion, for 'asset' items only — traces this
    # line item to the exact Inventory row it was converted into.
    converted_inventory_id = Column(UUID(as_uuid=True), ForeignKey("inventory.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class InventoryTransaction(Base):
    __tablename__ = "inventory_transactions"
    transaction_type = Column(String(30), nullable=False, default="legacy", server_default="legacy")
    expense_item_id = Column(UUID(as_uuid=True), ForeignKey("expense_items.id"), nullable=True, unique=True)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    inventory_id = Column(UUID(as_uuid=True), ForeignKey("inventory.id"), nullable=False)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=True)
    change_qty = Column(Numeric, nullable=False)
    reason = Column(String(100), nullable=True)
    performed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    organization_id = Column(UUID(as_uuid=True), ForeignKey("organizations.id"), nullable=True)
    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=True)
    action = Column(String(100), nullable=False)
    entity_type = Column(String(30), nullable=True)
    entity_id = Column(UUID(as_uuid=True), nullable=True)
    details = Column(JSONB, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class CiteMember(OrganizationScoped, Base):
    """
    Pre-approved roster of CITE Department officers/advisers/treasurers.
    Managed by admin/super_admin via routers/cite_members.py.
    POST /auth/register validates a self-registering user's email against
    this table and auto-assigns the role/position recorded here — nobody
    can choose their own role at self-registration, only claim the one
    already assigned to their email on this list.

    department_id optionally links the roster entry to a school department
    (see the Department model above) — useful for advisers tagged to the
    specific department they advise from.
    """
    __tablename__ = "cite_members"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    full_name = Column(String(150), nullable=False)
    email = Column(String(150), nullable=False, unique=True)
    role = Column(String(20), nullable=False)  # 'officer' | 'adviser' | 'treasurer'
    position = Column(String(50), nullable=True)
    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=True)
    # Set once this entry is used to create an account — prevents the
    # same roster entry being claimed twice.
    claimed_by_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    department = relationship("Department")


class OtpToken(Base):
    """
    Tracks the validity window of a one-time code — either the
    temporary password emailed at account creation ('initial_setup')
    or a password-reset verification code ('password_reset').

    For 'initial_setup': the OTP is ALSO the user's actual
    password_hash (so it works through the normal login endpoint) —
    this row's job is purely to say whether that temp password's
    window has expired, since users.password_hash alone carries no
    expiry information.

    For 'password_reset': code_hash IS the verification secret,
    checked directly and separately from users.password_hash — the
    user's real password isn't touched until the code is verified.
    """
    __tablename__ = "otp_tokens"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    purpose = Column(String(20), nullable=False)  # 'registration' | 'initial_setup' | 'password_reset'
    code_hash = Column(Text, nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    used_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class EventProposalLetter(Base):
    """
    A formal proposal-letter document submitted for an event —
    deliberately separate from the Event record itself
    (title/description/status/budget). This is the entire reason the
    sds_staff role exists: SDS's only permission in this system is
    reading these letters.
    """
    __tablename__ = "event_proposal_letters"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False)
    title = Column(String(200), nullable=False)
    document_url = Column(Text, nullable=False)
    submitted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
