"""SAS-SDS-FO-020 version 001: local Manila schedules and paper evidence."""
from datetime import date, time, datetime
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID
from copy import copy
from pydantic import AfterValidator, BaseModel, ConfigDict, Field, field_validator, model_validator, create_model


class StrictModel(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)


class Details(StrictModel):
    title: str = Field(min_length=1, max_length=180)
    organization_name: str = Field(min_length=1, max_length=150)
    school_year: str = Field(pattern=r'^\d{4}-\d{4}$', max_length=9)
    department_type: str = Field(min_length=1, max_length=80)
    department: str = Field(min_length=1, max_length=100)
    course: str = Field(default='', max_length=100)
    proposal_date: date
    activity_date: date
    start_time: time
    end_time: time
    setting: Literal['on_campus', 'off_campus', 'online']
    off_campus_agreement: bool = False
    modality: Literal['face_to_face', 'online', 'hybrid']
    venue: str = Field(min_length=1, max_length=200)
    persons_in_charge: str = Field(min_length=1, max_length=250)
    attire: str = Field(default='', max_length=100)
    activity_types: list[str] = Field(min_length=1, max_length=8)
    scope: Literal['departmental', 'organizational']
    expected_students: int = Field(ge=1, le=100000)
    program_types: list[str] = Field(min_length=1, max_length=8)
    rationale: str = Field(min_length=1, max_length=1800)
    objectives: str = Field(min_length=1, max_length=1200)
    core_values: list[Literal['courage', 'compassion', 'community_oriented', 'humility', 'interiority', 'missionary_spirit']] = Field(min_length=1, max_length=6)
    egas: list[Literal[1, 2, 3, 4]] = Field(min_length=1, max_length=4)
    emergency_plan: str = Field(min_length=1, max_length=600)
    total_budget: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    funding_source: str = Field(min_length=1, max_length=150)
    additional_information: str = Field(default='', max_length=10000)
    excuse_arrangement: str = Field(default='', max_length=400)

    @model_validator(mode='after')
    def schedule(self):
        if self.start_time.tzinfo or self.end_time.tzinfo or self.end_time <= self.start_time:
            raise ValueError('Use same-day local times; end must follow start')
        if self.proposal_date > self.activity_date:
            raise ValueError('Proposal date cannot follow activity date')
        if self.setting == 'online' and self.modality != 'online':
            raise ValueError('Online setting requires online modality')
        if (self.setting == 'off_campus') != self.off_campus_agreement:
            raise ValueError('Off-campus activities require agreement acknowledgment')
        if any(not x or len(x) > 80 for x in self.activity_types + self.program_types):
            raise ValueError('Checkbox labels must contain 1–80 characters')
        return self


class ProgramItem(StrictModel):
    start: time
    end: time
    activity: str = Field(min_length=1, max_length=160)


class BudgetItem(StrictModel):
    particulars: str = Field(min_length=1, max_length=120)
    quantity: int = Field(default=1, ge=1, le=100000, strict=True)
    unit_cost: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    amount: Decimal = Field(ge=0, max_digits=12, decimal_places=2)


class SupportRequest(StrictModel):
    type: Literal['budget', 'vehicle', 'food', 'room', 'sound', 'microphone', 'projector', 'chairs', 'tables', 'diverse_needs', 'other']
    quantity: int = Field(ge=1, le=100000)
    specify: str = Field(default='', max_length=150)


class AffectedClass(StrictModel):
    year_level: str = Field(min_length=1, max_length=40)
    subject: str = Field(min_length=1, max_length=80)
    class_date: date
    start: time
    end: time
    professor: str = Field(min_length=1, max_length=100)


class Clearance(StrictModel):
    parents_consent: Literal['yes', 'not_applicable']
    parents_consent_reason: str = Field(default='', max_length=5000)
    attachments: str = Field(min_length=1, max_length=5000)
    class_interruption: Literal['yes', 'none']
    class_interruption_remarks: str = Field(default='', max_length=5000)
    medical_exam: Literal['yes', 'not_applicable']
    medical_exam_reason: str = Field(default='', max_length=5000)
    report_of_compliance: Literal['yes', 'not_applicable']
    report_of_compliance_reason: str = Field(default='', max_length=5000)
    student_personnel_ratio: str = Field(min_length=1, max_length=5000)

    @model_validator(mode='after')
    def reasons(self):
        for name in ('parents_consent', 'medical_exam', 'report_of_compliance'):
            if getattr(self, name) == 'not_applicable' and not getattr(self, name + '_reason'):
                raise ValueError(name + ' needs a Not Applicable reason')
        if self.class_interruption == 'yes' and not self.class_interruption_remarks:
            raise ValueError('Class interruption requires remarks')
        return self


class Version(StrictModel):
    expected_version: int = Field(ge=1)


def _partial_details():
    fields = {}
    for name, original in Details.model_fields.items():
        field = copy(original)
        field.default = None
        fields[name] = (original.annotation, field)
    return create_model('PartialDetails', __base__=StrictModel, **fields)


PartialDetails = _partial_details()


class DraftWrite(Version):
    details: PartialDetails


class CollectionWrite(Version):
    items: list[dict] = Field(max_length=16)


class ClearanceWrite(Version):
    clearance: Clearance


class ReturnWrite(Version):
    remarks: str = Field(min_length=1, max_length=1000)


class CheckpointWrite(Version):
    signer_name: str = Field(min_length=1, max_length=150)
    signer_reference: str = Field(min_length=1, max_length=100)
    assigned_user_id: UUID | None = None
    physical_signature_date: date
    remarks: str = Field(default='', max_length=300)
    recorded_on_behalf: bool = True


class EvaluationWrite(Version):
    outcome: Literal['conducted', 'canceled']
    remarks: str = Field(min_length=1, max_length=1000)


COLLECTIONS = {'program-flow': ProgramItem, 'budget-items': BudgetItem,
               'support-requests': SupportRequest, 'affected-classes': AffectedClass}


def validate_clearance(clearance, collections):
    """Part 4 is the SDS Office's own section, complete before it signs."""
    c = Clearance.model_validate(clearance)
    if bool(collections.get('affected-classes')) != (c.class_interruption == 'yes'):
        raise ValueError('SDS clearance must match declared class interruptions')
    return c


def validate_submission(details, collections, clearance):
    """Parts 1-3, the proposer's. Part 4 is filled by the SDS Office during
    review, so it is only checked here if it has already been filled in."""
    d = Details.model_validate(details)
    if clearance:
        validate_clearance(clearance, collections)
    parsed = {key: [model.model_validate(row) for row in collections.get(key, [])]
              for key, model in COLLECTIONS.items()}
    if not parsed['program-flow']:
        raise ValueError('Program flow is required')
    if sum((row.amount for row in parsed['budget-items']), Decimal(0)) != d.total_budget:
        raise ValueError('Budget breakdown must exactly equal total budget')
    for row in parsed['program-flow']:
        if row.start.tzinfo or row.end.tzinfo or not (d.start_time <= row.start < row.end <= d.end_time):
            raise ValueError('Program flow must fit inside the activity window')
    for row in parsed['affected-classes']:
        if (row.start.tzinfo or row.end.tzinfo or row.class_date != d.activity_date
                or row.start >= row.end or row.start >= d.end_time or row.end <= d.start_time):
            raise ValueError('Affected classes must overlap the activity window')
    return d


def _valid_section_remarks(value):
    allowed = {'activity_details', 'budget', 'support_requests', 'additional_information', 'clearance', 'other'}
    if any(key not in allowed or not isinstance(text, str) or len(text) > 1000 for key, text in value.items()):
        raise ValueError('Section remarks contain an unsupported section or exceed 1000 characters')
    return {key: text.strip() for key, text in value.items() if text.strip()}


SectionRemarks = Annotated[dict[str, str], AfterValidator(_valid_section_remarks)]


class SDSReviewWrite(Version):
    overall_remarks: str = Field(default='', max_length=3000)
    section_remarks: SectionRemarks = Field(default_factory=dict)
    signature_strokes: list[list[dict[str, float]]] = Field(min_length=1, max_length=80)

    @field_validator('signature_strokes')
    @classmethod
    def valid_strokes(cls, value):
        if sum(len(stroke) for stroke in value) > 5000 or any(not stroke for stroke in value):
            raise ValueError('Signature drawing is empty or too complex')
        for stroke in value:
            for point in stroke:
                if set(point) != {'x', 'y'} or not all(0 <= point[key] <= 1 for key in ('x', 'y')):
                    raise ValueError('Signature points must be normalized between 0 and 1')
        return value


class ReviewNotesWrite(Version):
    overall_remarks: str = Field(default='', max_length=3000)
    section_remarks: SectionRemarks = Field(default_factory=dict)


class DecisionWrite(Version):
    remarks: str = Field(min_length=1, max_length=3000)
    section_remarks: SectionRemarks | None = None  # None keeps the section remarks already saved


# Response models are separate from writes: drafts may contain only a few details.
# Routes exclude unset fields so reading legacy rows never invents stored values.
SAPState = Literal['draft', 'pending_department_review', 'pending_sap_review', 'revision_requested', 'sds_signed',
                   'approved', 'completed', 'rejected']


class SAPCollectionsOut(BaseModel):
    program_flow: list[ProgramItem] = Field(alias='program-flow')
    budget_items: list[BudgetItem] = Field(alias='budget-items')
    support_requests: list[SupportRequest] = Field(alias='support-requests')
    affected_classes: list[AffectedClass] = Field(alias='affected-classes')


class SAPAttachmentOut(BaseModel):
    id: UUID
    category: str
    display_name: str
    file_name: str
    content_type: str
    sha256: str
    uploaded_at: str


class SAPReviewOut(BaseModel):
    overall_remarks: str
    section_remarks: dict[str, str]
    signed_by: UUID | None
    signed_at: str | None
    signed_pdf_sha256: str | None


class SAPEvaluationOut(BaseModel):
    outcome: Literal['conducted', 'canceled']
    remarks: str
    evaluated_by: UUID
    evaluated_at: datetime


class SAPProposalOut(BaseModel):
    id: UUID
    event_id: UUID
    state: SAPState
    version: int
    revision_no: int
    return_remarks: str | None
    returned_by: Literal['moderator', 'dean', 'sds'] | None
    form_code: str
    form_version: str
    details: PartialDetails
    clearance: Clearance | None
    collections: SAPCollectionsOut
    attachments: list[SAPAttachmentOut]
    sds_review: SAPReviewOut | None
    evaluation: SAPEvaluationOut | None


class SAPCheckpointEvidenceOut(BaseModel):
    signer_name: str
    signer_reference: str
    assigned_user_id: UUID | None
    physical_signature_date: date
    remarks: str
    recorded_on_behalf: bool


class SAPCheckpointOut(BaseModel):
    id: UUID
    slot: int
    position: str
    display_label: str
    revision_no: int
    status: Literal['recorded', 'pending']
    actionable: bool
    evidence: SAPCheckpointEvidenceOut | None
    recorded_by: UUID | None
    recorded_at: datetime | None


class SAPWorkflowOut(BaseModel):
    state: SAPState
    revision_no: int
    version: int
    completed_count: int
    total_count: int
    steps: list[SAPCheckpointOut]


class SAPDownloadOut(BaseModel):
    url: str
    expires_in: int
    sha256: str


class SAPVerificationOut(BaseModel):
    proposal_id: UUID
    form_code: str
    form_version: str
    revision_no: int
    approval_state: SAPState | Literal['superseded']
    approved: bool
    verified_at: datetime
