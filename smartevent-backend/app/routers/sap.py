"""Backend-only SAP API. SDS records physical evidence, not e-signatures."""
from datetime import date, timezone, timedelta
from io import BytesIO
from uuid import UUID
import hashlib
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, Query
from fastapi.responses import Response
from pydantic import ValidationError
from sqlalchemy.orm import Session
from app.config import settings
from app.database import get_db
from app.dependencies import require_active_account
from app.models import User, DocumentRouting, Approval
from app.models_sap import SAPProposal, SAPItem, SAPRevision, SAPCheckpoint, SAPFinalCopy, SAPEvaluation
from app.schemas_sap import Details, DraftWrite, Version, CollectionWrite, ClearanceWrite, ReturnWrite, CheckpointWrite, EvaluationWrite, COLLECTIONS
from app.services import sap, storage
from app.services.sap_pdf import render_proposal
from app.services.closure import institution_today, ensure_post_requirements
from app.services.compliance import require_pre_activity_clearance

router = APIRouter(prefix='/events/{event_id}/sap-proposal', tags=['SAP'])
public_router = APIRouter(tags=['SAP verification'])


@router.post('', status_code=201)
def create(event_id: UUID, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, existing = sap.load(db, event_id, user, write=True, proposer=True, required=False)
    if existing or event.status != 'draft':
        raise HTTPException(409, 'Create SAP only for an unsubmitted draft event')
    if db.query(DocumentRouting.id).filter_by(event_id=event.id).first() or db.query(Approval.id).filter_by(entity_type='event', entity_id=event.id).first():
        raise HTTPException(409, 'An event with existing generic routing cannot switch workflows')
    if event.organization_id is None:
        raise HTTPException(409, 'Assign an organization first')
    proposal = SAPProposal(event_id=event.id)
    db.add(proposal)
    db.flush()
    return sap.save(db, event, proposal, user, 'sap_created')


@router.get('')
def get(event_id: UUID, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    _, proposal = sap.load(db, event_id, user)
    return sap.output(db, proposal)


@router.patch('')
def update(event_id: UUID, payload: DraftWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, proposer=True)
    sap.check_version(proposal, payload.expected_version, editable=True)
    proposal.details = {**proposal.details, **payload.details.model_dump(mode='json', exclude_unset=True)}
    try:
        complete_details = Details.model_validate(proposal.details)
    except ValidationError:
        complete_details = None  # Incomplete draft; validate the whole form at submit.
    if complete_details is not None:
        sap.sync_event(db, event, complete_details)
    proposal.clearance = None  # Material draft changes need fresh SDS confirmation.
    return sap.save(db, event, proposal, user, 'sap_details_updated')


@router.put('/sds-clearance')
def clearance(event_id: UUID, payload: ClearanceWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, payload.expected_version, editable=True)
    proposal.clearance = payload.clearance.model_dump(mode='json')
    return sap.save(db, event, proposal, user, 'sap_clearance_updated')


@router.post('/submit')
def submit(event_id: UUID, payload: Version, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, proposer=True)
    sap.check_version(proposal, payload.expected_version, editable=True)
    if not settings.sap_verification_base_url:
        raise HTTPException(503, 'Configure SAP_VERIFICATION_BASE_URL before issuing controlled copies')
    return sap.submit(db, event, proposal, user, settings.sap_verification_base_url)


@router.get('/workflow')
def workflow(event_id: UUID, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    _, proposal = sap.load(db, event_id, user)
    return sap.workflow(db, proposal)


@router.post('/workflow/{step_id}/record')
def record(event_id: UUID, step_id: UUID, payload: CheckpointWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, payload.expected_version)
    if proposal.state != 'pending_sap_review':
        raise HTTPException(409, 'Only the current pending revision can receive checkpoints')
    rev = sap.revision(db, proposal)
    rows = sap.steps(db, rev)
    row = next((r for r in rows if r.id == step_id), None)
    if row is None:
        raise HTTPException(404, 'Checkpoint not found in the current revision')
    signed = {r.slot: r for r in rows if r.evidence}
    if row.evidence or not set(sap.prerequisites(row.slot)) <= signed.keys():
        raise HTTPException(409, 'Checkpoint already recorded or required predecessors incomplete')
    submitted_at = rev.submitted_at.replace(tzinfo=timezone.utc) if rev.submitted_at.tzinfo is None else rev.submitted_at
    submitted_day = submitted_at.astimezone(timezone(timedelta(hours=8))).date()
    if payload.physical_signature_date > institution_today() or payload.physical_signature_date < submitted_day:
        raise HTTPException(422, 'Physical signature must be dated between submission and today')
    for predecessor in sap.prerequisites(row.slot):
        if payload.physical_signature_date < date.fromisoformat(signed[predecessor].evidence['physical_signature_date']):
            raise HTTPException(422, 'Signature date cannot precede required predecessors')
    proposer = db.get(User, event.proposed_by)
    if row.slot == 1 and payload.assigned_user_id != event.proposed_by:
        raise HTTPException(422, 'Preparation attestation must identify the event proposer account')
    if row.slot != 1 and (payload.assigned_user_id == event.proposed_by or payload.signer_name.casefold() == proposer.full_name.strip().casefold()):
        raise HTTPException(403, 'Proposer cannot independently review their own proposal')
    if payload.assigned_user_id:
        account = db.get(User, payload.assigned_user_id)
        if account is None or not account.is_active or account.is_suspended:
            raise HTTPException(422, 'Assigned signer account must be active')
        if account.full_name.strip().casefold() != payload.signer_name.casefold():
            raise HTTPException(422, 'Signer name must match the assigned account')
    if not payload.recorded_on_behalf and payload.assigned_user_id != user.id:
        raise HTTPException(422, 'Recording another physical signer must be marked on behalf')
    for previous in signed.values():
        evidence = previous.evidence
        if (evidence['signer_reference'].casefold() == payload.signer_reference.casefold()
                or evidence['signer_name'].casefold() == payload.signer_name.casefold()
                or (payload.assigned_user_id and evidence.get('assigned_user_id') == str(payload.assigned_user_id))):
            raise HTTPException(422, 'All nine slots require distinct physical signers')
    row.evidence = payload.model_dump(mode='json', exclude={'expected_version'})
    row.recorded_by, row.recorded_at = user.id, sap.now()
    sap.save(db, event, proposal, user, 'sap_checkpoint_recorded', notify=True, details={'slot': row.slot, 'revision': proposal.revision_no})
    return sap.workflow(db, proposal)


@router.post('/return')
def return_proposal(event_id: UUID, payload: ReturnWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, payload.expected_version)
    if proposal.state != 'pending_sap_review':
        raise HTTPException(409, 'Only a pending SAP revision can be returned')
    proposal.state, proposal.return_remarks, proposal.clearance = 'revision_requested', payload.remarks, None
    event.status = 'draft'
    return sap.save(db, event, proposal, user, 'sap_returned', notify=True, details={'revision': proposal.revision_no, 'remarks': payload.remarks})


@router.get('/pdf')
def pdf(event_id: UUID, revision_no: int | None = Query(None, ge=1), db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    _, proposal = sap.load(db, event_id, user)
    if revision_no or proposal.state not in {'draft', 'revision_requested'}:
        rev = sap.revision(db, proposal, revision_no)
        data, number = rev.printable_pdf, rev.revision_no
    else:
        try:
            Details.model_validate(proposal.details)
            data, number = render_proposal(sap.snapshot(db, proposal), 'DRAFT'), 'draft'
        except ValueError as exc:
            raise HTTPException(422, str(exc)) from None
    return Response(data, media_type='application/pdf', headers={'Content-Disposition': f'attachment; filename="SAP-{event_id}-r{number}.pdf"', 'Cache-Control': 'private, no-store'})


@router.post('/final-signed-copy', status_code=201)
async def final_copy(event_id: UUID, expected_version: int = Form(..., ge=1), file: UploadFile = File(...), db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    if user.role != 'sds_staff':
        raise HTTPException(403, 'Only SDS staff may upload physical signature evidence')
    # Read bounded bytes before holding the event row lock during validation/upload.
    data = await file.read(storage.MAX_UPLOAD_BYTES + 1)
    if not data or len(data) > storage.MAX_UPLOAD_BYTES or not data.startswith(b'%PDF-'):
        raise HTTPException(422, 'Upload a PDF of at most 10 MB')
    from pypdf import PdfReader
    try:
        reader = PdfReader(BytesIO(data), strict=True)
        if reader.is_encrypted or len(reader.pages) != 6:
            raise ValueError('Expected six unencrypted pages')
        root = reader.trailer['/Root']
        if '/OpenAction' in root or '/AA' in root or '/AcroForm' in root or '/Names' in root or any('/Annots' in p or '/AA' in p for p in reader.pages):
            raise ValueError('Upload a flattened scan without active content or attachments')
    except Exception:
        raise HTTPException(422, 'Expected a valid, flattened, six-page PDF scan without active content') from None
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, expected_version)
    if proposal.state != 'pending_sap_review':
        raise HTTPException(409, 'Final scan can only approve the current pending revision')
    rev = sap.revision(db, proposal)
    rows = sap.steps(db, rev)
    if len(rows) != 9 or any(not row.evidence for row in rows):
        raise HTTPException(409, 'Record all nine physical signature checkpoints first')
    require_pre_activity_clearance(db, event)
    try:
        ref = storage.upload_proposal_letter(data, 'application/pdf', 'pdf', user.id, event.organization_id)
    except (storage.StorageError, RuntimeError):
        raise HTTPException(503, 'Private storage is unavailable; no approval was recorded') from None
    db.add(SAPFinalCopy(revision_id=rev.id, storage_ref=ref, sha256=hashlib.sha256(data).hexdigest(), uploaded_by=user.id))
    proposal.state, event.status = 'approved', 'approved'
    return sap.save(db, event, proposal, user, 'sap_approved_with_physical_evidence', notify=True)


@router.get('/final-signed-copy')
def signed_copy(event_id: UUID, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    _, proposal = sap.load(db, event_id, user, sds=True)
    rev = sap.revision(db, proposal)
    row = db.query(SAPFinalCopy).filter_by(revision_id=rev.id).first()
    if row is None:
        raise HTTPException(404, 'Final signed copy not available')
    try:
        return {'url': storage.signed_file_url(row.storage_ref), 'expires_in': storage.SIGNED_URL_SECONDS, 'sha256': row.sha256}
    except (storage.StorageError, RuntimeError):
        raise HTTPException(503, 'Private storage is unavailable') from None


@router.post('/evaluation')
def evaluate(event_id: UUID, payload: EvaluationWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, payload.expected_version)
    if proposal.state != 'approved' or db.query(SAPEvaluation.id).filter_by(proposal_id=proposal.id).first():
        raise HTTPException(409, 'Evaluate an approved proposal once')
    if payload.outcome == 'conducted' and (event.event_date is None or event.event_date > institution_today()):
        raise HTTPException(422, 'Cannot record a future activity as conducted')
    if payload.outcome == 'conducted':
        ensure_post_requirements(db, event)
    db.add(SAPEvaluation(proposal_id=proposal.id, outcome=payload.outcome, remarks=payload.remarks, evaluated_by=user.id))
    # Completed means lifecycle administration is complete, not necessarily conducted.
    # Canceled evaluations remain explicit; no invented event status or attendance.
    event.status, proposal.state = 'completed', 'completed'
    event.completed_on, event.completed_at, event.completed_by = institution_today(), sap.now(), user.id
    return sap.save(db, event, proposal, user, 'sap_evaluated', notify=True, details={'outcome': payload.outcome, 'remarks': payload.remarks})


@router.put('/{collection}')
def replace_collection(event_id: UUID, collection: str, payload: CollectionWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    model = COLLECTIONS.get(collection)
    if model is None:
        raise HTTPException(404, 'Unknown SAP collection')
    event, proposal = sap.load(db, event_id, user, write=True, proposer=True)
    sap.check_version(proposal, payload.expected_version, editable=True)
    try:
        rows = [model.model_validate(row).model_dump(mode='json') for row in payload.items]
    except ValidationError:
        raise HTTPException(422, 'Invalid collection fields; see the SAP contract') from None
    db.query(SAPItem).filter_by(proposal_id=proposal.id, kind=collection).delete(synchronize_session=False)
    db.add_all([SAPItem(proposal_id=proposal.id, kind=collection, ordinal=i, data=row) for i, row in enumerate(rows)])
    proposal.clearance = None
    return sap.save(db, event, proposal, user, 'sap_collection_replaced')


@public_router.get('/sap/verify/{token}')
def verify(token: str, response: Response, db: Session = Depends(get_db)):
    response.headers['Cache-Control'] = 'no-store'
    if len(token) != 43:
        raise HTTPException(404, 'Verification not found')
    rev = db.query(SAPRevision).filter_by(verification_token=token).first()
    if rev is None:
        raise HTTPException(404, 'Verification not found')
    proposal = db.get(SAPProposal, rev.proposal_id)
    approved = db.query(SAPFinalCopy.id).filter_by(revision_id=rev.id).first() is not None
    current = proposal.revision_no == rev.revision_no
    return {'proposal_id': proposal.id, 'form_code': proposal.form_code, 'form_version': proposal.form_version,
            'revision_no': rev.revision_no, 'approval_state': ('approved' if approved else proposal.state) if current else 'superseded',
            'approved': approved and current, 'verified_at': sap.now()}
