"""SAP 001 is independent of generic document routing."""
import uuid
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, JSON, LargeBinary, UniqueConstraint, CheckConstraint, and_, func, or_
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.hybrid import hybrid_property
from sqlalchemy.orm import deferred
from app.database import Base

# States in which a proposal is the SDS Office's work; before them it is the proposer's or the department's.
SDS_STATES = ('pending_sap_review', 'sds_signed', 'approved', 'completed', 'rejected')


class SAPProposal(Base):
    __tablename__ = 'sap_proposals'
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id = Column(UUID(as_uuid=True), ForeignKey('events.id'), nullable=False, unique=True)
    form_code = Column(String(30), nullable=False, default='SAS-SDS-FO-020')
    form_version = Column(String(10), nullable=False, default='001')
    state = Column(String(30), nullable=False, default='draft')
    version = Column(Integer, nullable=False, default=1)
    revision_no = Column(Integer, nullable=False, default=0)
    details = Column(JSON, nullable=False, default=dict)
    clearance = Column(JSON, nullable=True)
    return_remarks = Column(Text)
    returned_by = Column(String(10))
    __table_args__ = (CheckConstraint("state IN ('draft','pending_department_review','pending_sap_review','revision_requested','sds_signed','approved','completed','rejected')"),
                     CheckConstraint("returned_by IN ('moderator','dean','sds')"))

    @hybrid_property
    def seen_by_sds(self):
        """Whether the SDS Office may see it: it has reached the office, or the office itself returned it."""
        return self.state in SDS_STATES or (self.state == 'revision_requested' and self.returned_by == 'sds')

    @seen_by_sds.expression
    def seen_by_sds(cls):
        return or_(cls.state.in_(SDS_STATES), and_(cls.state == 'revision_requested', cls.returned_by == 'sds'))


class SAPItem(Base):
    __tablename__ = 'sap_items'
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    proposal_id = Column(UUID(as_uuid=True), ForeignKey('sap_proposals.id'), nullable=False, index=True)
    kind = Column(String(30), nullable=False)
    ordinal = Column(Integer, nullable=False)
    data = Column(JSON, nullable=False)
    __table_args__ = (UniqueConstraint('proposal_id', 'kind', 'ordinal'),
                     CheckConstraint("kind IN ('program-flow','budget-items','support-requests','affected-classes')"))


class SAPRevision(Base):
    __tablename__ = 'sap_revisions'
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    proposal_id = Column(UUID(as_uuid=True), ForeignKey('sap_proposals.id'), nullable=False, index=True)
    revision_no = Column(Integer, nullable=False)
    snapshot = Column(JSON, nullable=False)
    printable_pdf = Column(LargeBinary, nullable=False)
    pdf_sha256 = Column(String(64), nullable=False)
    verification_token = Column(String(64), nullable=False, unique=True)
    submitted_by = Column(UUID(as_uuid=True), ForeignKey('users.id'), nullable=False)
    submitted_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    __table_args__ = (UniqueConstraint('proposal_id', 'revision_no'),)


class SAPCheckpoint(Base):
    __tablename__ = 'sap_checkpoints'
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    revision_id = Column(UUID(as_uuid=True), ForeignKey('sap_revisions.id'), nullable=False, index=True)
    slot = Column(Integer, nullable=False)
    position = Column(String(200), nullable=False)
    label = Column(String(50), nullable=False)
    evidence = Column(JSON)
    recorded_by = Column(UUID(as_uuid=True), ForeignKey('users.id'))
    recorded_at = Column(DateTime(timezone=True))
    __table_args__ = (UniqueConstraint('revision_id', 'slot'), CheckConstraint('slot BETWEEN 1 AND 9'))


class SAPFinalCopy(Base):
    __tablename__ = 'sap_final_copies'
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    revision_id = Column(UUID(as_uuid=True), ForeignKey('sap_revisions.id'), nullable=False, unique=True)
    storage_ref = Column(Text, nullable=False)
    sha256 = Column(String(64), nullable=False)
    uploaded_by = Column(UUID(as_uuid=True), ForeignKey('users.id'), nullable=False)
    uploaded_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class SAPEvaluation(Base):
    __tablename__ = 'sap_evaluations'
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    proposal_id = Column(UUID(as_uuid=True), ForeignKey('sap_proposals.id'), nullable=False, unique=True)
    outcome = Column(String(20), nullable=False)
    remarks = Column(Text, nullable=False)
    evaluated_by = Column(UUID(as_uuid=True), ForeignKey('users.id'), nullable=False)
    evaluated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    __table_args__ = (CheckConstraint("outcome IN ('conducted','canceled')"),)


class SAPAttachment(Base):
    __tablename__ = 'sap_attachments'
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    proposal_id = Column(UUID(as_uuid=True), ForeignKey('sap_proposals.id'), nullable=False, index=True)
    revision_no = Column(Integer, nullable=False)
    category = Column(String(30), nullable=False)
    display_name = Column(String(150), nullable=False)
    file_name = Column(String(255), nullable=False)
    content_type = Column(String(80), nullable=False)
    storage_ref = Column(Text, nullable=False)
    sha256 = Column(String(64), nullable=False)
    uploaded_by = Column(UUID(as_uuid=True), ForeignKey('users.id'), nullable=False)
    uploaded_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


class SAPReview(Base):
    __tablename__ = 'sap_reviews'
    revision_id = Column(UUID(as_uuid=True), ForeignKey('sap_revisions.id'), primary_key=True)
    overall_remarks = Column(Text, nullable=False, default='')
    section_remarks = Column(JSON, nullable=False, default=dict)
    signature_strokes = deferred(Column(JSON))
    signed_by = Column(UUID(as_uuid=True), ForeignKey('users.id'))
    signed_at = Column(DateTime(timezone=True))
    signed_pdf = deferred(Column(LargeBinary))
    signed_pdf_sha256 = Column(String(64))
