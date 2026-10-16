"""Phase 2 records; existing participant/requirement tables remain authoritative."""

import uuid

from sqlalchemy import Boolean, CheckConstraint, Column, Date, DateTime, ForeignKey, ForeignKeyConstraint, Index, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class EventLogistics(Base):
    __tablename__ = "event_logistics"
    __table_args__ = (
        CheckConstraint("activity_location IN ('on_campus', 'off_campus')", name="logistics_location_check"),
        CheckConstraint("transport_mode IN ('none', 'institution', 'third_party')", name="logistics_transport_check"),
    )
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), primary_key=True)
    activity_location = Column(String(20), nullable=False)
    destination = Column(String(300), nullable=False)
    transport_mode = Column(String(20), nullable=False, default="none", server_default="none")
    transport_notes = Column(Text, nullable=True)
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())


class EventPersonnel(Base):
    __tablename__ = "event_personnel"
    __table_args__ = (UniqueConstraint("event_id", "staff_reference", name="uq_event_personnel_reference"),)
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False, index=True)
    staff_reference = Column(String(50), nullable=False)
    full_name = Column(String(150), nullable=False)
    position = Column(String(100), nullable=False)
    qualifications = Column(String(1000), nullable=False)
    is_active = Column(Boolean, nullable=False, default=True, server_default="true")


class EventVehicle(Base):
    __tablename__ = "event_vehicles"
    __table_args__ = (
        UniqueConstraint("event_id", "plate_number", name="uq_event_vehicle_plate"),
        UniqueConstraint("id", "event_id", name="uq_vehicle_id_event"),
    )
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False, index=True)
    plate_number = Column(String(30), nullable=False)
    operator_name = Column(String(150), nullable=False)
    driver_name = Column(String(150), nullable=False)
    out_of_line = Column(Boolean, nullable=False, default=False, server_default="false")
    is_active = Column(Boolean, nullable=False, default=True, server_default="true")


class EventComplianceDocument(Base):
    __tablename__ = "event_compliance_documents"
    __table_args__ = (
        UniqueConstraint("event_id", "document_key", name="uq_event_document_key"),
        ForeignKeyConstraint(["vehicle_id", "event_id"], ["event_vehicles.id", "event_vehicles.event_id"], name="compliance_document_vehicle_fk"),
        CheckConstraint("status IN ('SUBMITTED', 'VERIFIED', 'REJECTED')", name="event_document_status_check"),
        CheckConstraint("version > 0", name="event_document_version_check"),
        CheckConstraint("status = 'SUBMITTED' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)", name="event_document_review_check"),
        CheckConstraint("(vehicle_id IS NULL AND kind IN ('lgu_coordination', 'agency_acknowledgment', 'signed_attendance', 'debriefing_report', 'final_expense_report')) OR "
                        "(vehicle_id IS NOT NULL AND kind IN ('vehicle_registration', 'insurance', 'driver_license', 'roadworthiness', 'ltfrb_franchise', 'dot_accreditation', 'ltfrb_special_permit'))", name="event_document_kind_check"),
        Index("ix_compliance_document_vehicle_event", "vehicle_id", "event_id"),
    )
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False, index=True)
    vehicle_id = Column(UUID(as_uuid=True), nullable=True, index=True)
    document_key = Column(String(100), nullable=False)
    kind = Column(String(40), nullable=False)
    document_url = Column(Text, nullable=False)
    reference_number = Column(String(150), nullable=False)
    valid_until = Column(Date, nullable=True)
    validity_confirmed = Column(Boolean, nullable=False, default=False, server_default="false")
    status = Column(String(20), nullable=False, default="SUBMITTED", server_default="SUBMITTED")
    version = Column(Integer, nullable=False, default=1, server_default="1")
    submitted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    submitted_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    reviewed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True, index=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
    remarks = Column(Text, nullable=True)


class EventParallelActivity(Base):
    __tablename__ = "event_parallel_activities"
    __table_args__ = (
        UniqueConstraint("participant_id", name="uq_parallel_participant"),
        ForeignKeyConstraint(["participant_id", "event_id"], ["event_participants.id", "event_participants.event_id"], name="parallel_participant_event_fk"),
        CheckConstraint("status IN ('ASSIGNED', 'SUBMITTED', 'VERIFIED', 'REJECTED')", name="parallel_status_check"),
        CheckConstraint("version > 0", name="parallel_version_check"),
        CheckConstraint("evidence_mode IS NULL OR evidence_mode IN ('digital', 'physical')", name="parallel_evidence_check"),
        CheckConstraint("status NOT IN ('VERIFIED', 'REJECTED') OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)", name="parallel_review_check"),
        Index("ix_parallel_participant_event", "participant_id", "event_id"),
    )
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey("events.id"), nullable=False, index=True)
    participant_id = Column(UUID(as_uuid=True), nullable=False)
    title = Column(String(200), nullable=False)
    learning_objectives = Column(Text, nullable=False)
    instructions = Column(Text, nullable=False)
    reason = Column(Text, nullable=False)
    due_date = Column(Date, nullable=True)
    assigned_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    is_active = Column(Boolean, nullable=False, default=True, server_default="true")
    status = Column(String(20), nullable=False, default="ASSIGNED", server_default="ASSIGNED")
    version = Column(Integer, nullable=False, default=1, server_default="1")
    document_url = Column(Text, nullable=True)
    submitted_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True, index=True)
    submitted_at = Column(DateTime(timezone=True), nullable=True)
    evidence_mode = Column(String(20), nullable=True)
    reviewed_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True, index=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
    remarks = Column(Text, nullable=True)
