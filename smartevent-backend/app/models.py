
import uuid

from sqlalchemy import (
    Boolean, CheckConstraint, Column, Date, DateTime, Time, ForeignKey, ForeignKeyConstraint, Index, Integer, Numeric, String, Text, UniqueConstraint, func, text,
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship, declared_attr

from app.database import Base


class Department(Base):
    __tablename__ = "departments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    code = Column(String(20), nullable=False, unique=True)
    name = Column(String(150), nullable=False)
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
    login_failed_attempts = Column(Integer, nullable=False, default=0, server_default="0")
    login_locked_until = Column(DateTime(timezone=True), nullable=True)
    role = Column(String(20), nullable=False)
    position = Column(String(50), nullable=True)


    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    is_suspended = Column(Boolean, nullable=False, default=False)


    must_change_password = Column(Boolean, nullable=False, default=False)
    fcm_token = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now())

    department = relationship("Department")
    organization = relationship("Organization")

    @property
    def organization_name(self):
        return self.organization.name if self.organization is not None else None


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (Index('uq_registration_notification', 'user_id', 'kind', unique=True,
                           postgresql_where=text("kind = 'registration_confirmation'"),
                           sqlite_where=text("kind = 'registration_confirmation'")),)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    kind = Column(String(50), nullable=False)
    title = Column(String(200), nullable=False)
    body = Column(Text, nullable=False)
    payload = Column(JSONB, nullable=True)
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
    __table_args__ = (
        CheckConstraint("review_round > 0", name="event_review_round_positive"),
        CheckConstraint('(start_time IS NULL AND end_time IS NULL) OR '
                        '(start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time)',
                        name='event_local_time_window'),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=True)
    category_id = Column(UUID(as_uuid=True), ForeignKey("categories.id"), nullable=True)


    school_year = Column(String(9), nullable=True)
    semester = Column(String(10), nullable=True)
    event_scope = Column(String(20), nullable=True)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    proposed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    status = Column(String(40), nullable=False, default="draft")
    review_round = Column(Integer, nullable=False, default=1, server_default="1")
    completed_on = Column(Date, nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    completed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True, index=True)
    event_date = Column(Date, nullable=True)
    start_time = Column(Time, nullable=True)
    end_time = Column(Time, nullable=True)
    estimated_cost = Column(Numeric(12, 2), default=0)
    allocated_budget = Column(Numeric(12, 2), nullable=False, default=0)
    remaining_budget = Column(Numeric(12, 2), nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now())

    category = relationship("Category")


class DocumentRouting(Base):
    __tablename__ = "document_routing"
    __table_args__ = (
        UniqueConstraint("event_id", "review_round", "step_order", name="uq_routing_event_round_step"),
        UniqueConstraint("event_id", "review_round", "signatory_id", name="uq_routing_event_round_signatory"),
        CheckConstraint("review_round > 0 AND step_order > 0", name="routing_positive_order"),
        CheckConstraint("status IN ('pending', 'approved', 'rejected')", name="routing_status_check"),
        CheckConstraint("(status = 'pending' AND decided_at IS NULL) OR (status <> 'pending' AND decided_at IS NOT NULL)", name="routing_decision_check"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False)
    review_round = Column(Integer, nullable=False, default=1, server_default="1")
    step_order = Column(Integer, nullable=False)
    signatory_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    status = Column(String(20), nullable=False, default="pending", server_default="pending")
    remarks = Column(Text, nullable=True)
    decided_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class RequirementPreset(Base):
    __tablename__ = "requirement_presets"
    __table_args__ = (
        CheckConstraint("phase IN ('pre_activity', 'post_activity')", name="preset_phase_check"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    code = Column(String(50), nullable=False, unique=True)
    name = Column(String(150), nullable=False)
    description = Column(Text, nullable=True)
    phase = Column(String(20), nullable=False)
    requires_notarization = Column(Boolean, nullable=False, default=False, server_default="false")
    is_sensitive = Column(Boolean, nullable=False, default=False, server_default="false")
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class EventParticipant(Base):
    __tablename__ = "event_participants"
    __table_args__ = (
        UniqueConstraint("event_id", "student_number", name="uq_participant_event_student"),
        UniqueConstraint("id", "event_id", name="uq_participant_id_event"),
        CheckConstraint("length(trim(student_number)) > 0 AND length(trim(full_name)) > 0", name="participant_identity_check"),
        CheckConstraint("participation_mode IN ('attending', 'parallel')", name="participant_mode_check"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False)
    student_number = Column(String(50), nullable=False)
    full_name = Column(String(150), nullable=False)
    email = Column(String(150), nullable=True)
    participation_mode = Column(String(20), nullable=False, default="attending", server_default="attending")
    is_active = Column(Boolean, nullable=False, default=True, server_default="true")
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class EventRequirement(Base):
    __tablename__ = "event_requirements"
    __table_args__ = (
        UniqueConstraint("id", "event_id", name="uq_requirement_id_event"),
        UniqueConstraint("event_id", "preset_id", name="uq_requirement_event_preset"),
        CheckConstraint("phase IN ('pre_activity', 'post_activity')", name="requirement_phase_check"),
        CheckConstraint("length(trim(name)) > 0", name="requirement_name_check"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False, index=True)
    preset_id = Column(UUID(as_uuid=True), ForeignKey("requirement_presets.id"), nullable=True, index=True)
    name = Column(String(150), nullable=False)
    description = Column(Text, nullable=True)
    phase = Column(String(20), nullable=False)
    is_required = Column(Boolean, nullable=False, default=True, server_default="true")
    requires_notarization = Column(Boolean, nullable=False, default=False, server_default="false")
    is_sensitive = Column(Boolean, nullable=False, default=False, server_default="false")
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class StudentComplianceRecord(Base):
    __tablename__ = "student_compliance_records"
    __table_args__ = (
        UniqueConstraint("participant_id", "requirement_id", name="uq_compliance_participant_requirement"),
        ForeignKeyConstraint(["participant_id", "event_id"], ["event_participants.id", "event_participants.event_id"], name="compliance_participant_event_fk"),
        ForeignKeyConstraint(["requirement_id", "event_id"], ["event_requirements.id", "event_requirements.event_id"], name="compliance_requirement_event_fk"),
        CheckConstraint("status IN ('MISSING', 'SUBMITTED', 'VERIFIED', 'REJECTED')", name="compliance_status_check"),
        CheckConstraint("status NOT IN ('VERIFIED', 'REJECTED') OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)", name="compliance_review_check"),
        CheckConstraint("version > 0", name="compliance_version_check"),
        CheckConstraint("evidence_mode IS NULL OR evidence_mode IN ('digital', 'physical')", name="compliance_evidence_mode_check"),
        Index("ix_compliance_participant_event", "participant_id", "event_id"),
        Index("ix_compliance_requirement_event", "requirement_id", "event_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False, index=True)
    participant_id = Column(UUID(as_uuid=True), nullable=False)
    requirement_id = Column(UUID(as_uuid=True), nullable=False, index=True)
    status = Column(String(20), nullable=False, default="MISSING", server_default="MISSING")
    document_url = Column(Text, nullable=True)
    submitted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True, index=True)
    submitted_at = Column(DateTime(timezone=True), nullable=True)
    evidence_mode = Column(String(20), nullable=True)
    notarization_confirmed = Column(Boolean, nullable=False, default=False, server_default="false")
    version = Column(Integer, nullable=False, default=1, server_default="1")
    reviewed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True, index=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
    remarks = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())


class Approval(Base):
    __tablename__ = "approvals"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    entity_type = Column(String(20), nullable=False)
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


    is_draft = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now())


class ExpenseItem(Base):
    __tablename__ = "expense_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    expense_id = Column(UUID(as_uuid=True), ForeignKey("expenses.id"), nullable=False)
    name = Column(String(150), nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    category = Column(String(20), nullable=False)
    quantity = Column(Integer, nullable=False, default=1, server_default="1")
    unit = Column(String(30), nullable=False, default="pcs", server_default="pcs")


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
    __tablename__ = "cite_members"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    full_name = Column(String(150), nullable=False)
    email = Column(String(150), nullable=False, unique=True)
    role = Column(String(20), nullable=False)
    position = Column(String(50), nullable=True)
    department_id = Column(UUID(as_uuid=True), ForeignKey("departments.id"), nullable=True)


    claimed_by_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    department = relationship("Department")


class OtpToken(Base):
    __tablename__ = "otp_tokens"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    purpose = Column(String(20), nullable=False)
    code_hash = Column(Text, nullable=False)
    failed_attempts = Column(Integer, nullable=False, default=0, server_default="0")
    expires_at = Column(DateTime(timezone=True), nullable=False)
    used_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class EventProposalLetter(Base):
    __tablename__ = "event_proposal_letters"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False)
    title = Column(String(200), nullable=False)
    document_url = Column(Text, nullable=False)
    submitted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
