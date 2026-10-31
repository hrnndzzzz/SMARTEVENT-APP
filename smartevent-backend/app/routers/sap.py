"""SAP proposal API for supporting files, SDS review, e-signing, and paper evidence."""
from datetime import date, timezone, timedelta
from io import BytesIO
from uuid import UUID
import hashlib
import logging
from pathlib import PurePath
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, Query
from fastapi.responses import Response
from pydantic import ValidationError
from sqlalchemy.orm import Session
from app.config import settings
from app.database import get_db
from app.dependencies import require_active_account
from app.models import User, DocumentRouting, Approval
from app.models_sap import SAPProposal, SAPItem, SAPRevision, SAPCheckpoint, SAPFinalCopy, SAPEvaluation, SAPAttachment, SAPReview
from app.schemas_sap import Details, DraftWrite, Version, CollectionWrite, ClearanceWrite, ReturnWrite, DecisionWrite, CheckpointWrite, EvaluationWrite, SDSReviewWrite, ReviewNotesWrite, COLLECTIONS, validate_clearance
from app.schemas_sap import (SAPProposalOut, SAPWorkflowOut, SAPAttachmentOut,
                             SAPDownloadOut, SAPVerificationOut)
from app.services import sap, storage
from app.services.sap_pdf import render_proposal
from app.services.closure import institution_today, ensure_post_requirements
from app.services.compliance import require_pre_activity_clearance

router = APIRouter(prefix='/events/{event_id}/sap-proposal', tags=['SAP'])
public_router = APIRouter(tags=['SAP verification'])
logger = logging.getLogger(__name__)


def _with_clearance(rev, proposal):
    """The sent revision as the SDS Office sees it: Part 4 is theirs to fill
    in while reviewing it, so the current revision takes the latest Part 4.
    Revisions are frozen (sap_revision_immutable), which is why it is not
    written back; the signed PDF is what records it."""
    if rev.revision_no != proposal.revision_no:
        return rev.snapshot
    return {**rev.snapshot, 'clearance': proposal.clearance or rev.snapshot.get('clearance')}


# shortcut: per-process memory of recent printouts; each worker and each restart renders afresh.
_PRINTOUTS = {}


def _printout(proposal, number, render):
    """Word takes seconds per PDF. Every SAP change raises proposal.version,
    so the version and the revision name exactly one printout."""
    key = (proposal.id, proposal.version, number)
    data = _PRINTOUTS.get(key)
    if data is None:
        if len(_PRINTOUTS) >= 32:
            _PRINTOUTS.clear()
        data = _PRINTOUTS[key] = render()
    return data


def _record_remarks(db, rev, payload):
    """A decision's remarks go on the revision's review. The section remarks the SDS Office saved
    while reading stay unless the decision sends its own; a signed review cannot change."""
    review = db.query(SAPReview).filter_by(revision_id=rev.id).first()
    if review is None:
        review = SAPReview(revision_id=rev.id, section_remarks={})
        db.add(review)
    elif review.signed_at:
        raise HTTPException(409, 'Signed review is immutable; create a new revision')
    review.overall_remarks = payload.remarks
    if payload.section_remarks is not None:
        review.section_remarks = payload.section_remarks
    return review


def _cleanup_upload(db, ref):
    try:
        # A response can fail after commit. Never delete a now-referenced object.
        if db.query(SAPAttachment.id).filter_by(storage_ref=ref).first() or db.query(SAPFinalCopy.id).filter_by(storage_ref=ref).first():
            return
        storage.delete_uploaded_file(ref)
    except Exception:
        logger.warning('Could not safely remove an unreferenced SAP upload')


def _validated_attachment(data, content_type):
    if not data or len(data) > storage.MAX_UPLOAD_BYTES:
        raise HTTPException(422, 'Files must be between 1 byte and 10 MB')
    if content_type == 'application/pdf':
        from pypdf import PdfReader
        try:
            reader = PdfReader(BytesIO(data), strict=True)
            if not data.startswith(b'%PDF-') or reader.is_encrypted or not 1 <= len(reader.pages) <= 100:
                raise ValueError('Invalid PDF')
            from pypdf.generic import DictionaryObject, ArrayObject, IndirectObject
            stack, seen = [reader.trailer['/Root']], set()
            while stack:
                obj = stack.pop()
                if isinstance(obj, IndirectObject):
                    obj = obj.get_object()
                if not isinstance(obj, (DictionaryObject, ArrayObject)) or id(obj) in seen:
                    continue
                seen.add(id(obj))
                if len(seen) > 50000:
                    raise ValueError('PDF structure is too complex')
                if isinstance(obj, DictionaryObject):
                    if any(key in obj for key in ('/JS', '/JavaScript', '/AA', '/OpenAction', '/EmbeddedFiles', '/XFA')):
                        raise ValueError('Active content is not supported')
                    if obj.get('/S') in ('/JavaScript', '/Launch', '/SubmitForm', '/ImportData', '/Rendition'):
                        raise ValueError('Active content is not supported')
                    stack.extend(obj.values())
                else:
                    stack.extend(obj)
        except Exception:
            raise HTTPException(422, 'Attach a valid, unencrypted PDF of 1–100 pages without active content') from None
        return data, 'application/pdf', 'pdf'
    if content_type in {'image/png', 'image/jpeg', 'image/jpg'}:
        try:
            cleaned, mime = storage.prepare_image_for_upload(data)
            return cleaned, mime, 'jpg'
        except Exception:
            raise HTTPException(422, 'Attach a valid PNG or JPEG image') from None
    raise HTTPException(422, 'Attach a PDF, PNG, or JPEG file')



@router.post('', status_code=201, response_model=SAPProposalOut, response_model_exclude_unset=True)
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


@router.get('', response_model=SAPProposalOut, response_model_exclude_unset=True)
def get(event_id: UUID, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    _, proposal = sap.load(db, event_id, user)
    return sap.output(db, proposal)


@router.patch('', response_model=SAPProposalOut, response_model_exclude_unset=True)
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


@router.post('/attachments', status_code=201, response_model=SAPProposalOut, response_model_exclude_unset=True)
def upload_attachment(event_id: UUID, expected_version: int = Form(..., ge=1), category: str = Form(...),
                      file: UploadFile = File(...), db: Session = Depends(get_db),
                      user: User = Depends(require_active_account)):
    if category not in {'apf', 'pcf', 'appendix', 'roc_coc', 'other'}:
        raise HTTPException(422, 'Unsupported attachment category')
    event, proposal = sap.load(db, event_id, user, proposer=True)
    sap.check_version(proposal, expected_version, editable=True)
    data, content_type, extension = _validated_attachment(
        file.file.read(storage.MAX_UPLOAD_BYTES + 1), (file.content_type or '').lower())
    owner_id, organization_id = user.id, event.organization_id
    name = PurePath((file.filename or 'supporting-document').replace('\\', '/')).name[:255]
    # No row lock or database transaction is held while private storage responds.
    db.rollback()
    try:
        ref = storage.upload_proposal_letter(data, content_type, extension, owner_id, organization_id)
    except (storage.StorageError, RuntimeError):
        raise HTTPException(503, 'Private storage is unavailable') from None
    try:
        event, proposal = sap.load(db, event_id, user, write=True, proposer=True)
        sap.check_version(proposal, expected_version, editable=True)
        if event.organization_id != organization_id:
            raise HTTPException(409, 'Event organization changed; reload before uploading')
        if db.query(SAPAttachment.id).filter_by(proposal_id=proposal.id, revision_no=proposal.revision_no + 1).count() >= 30:
            raise HTTPException(422, 'A revision may contain at most 30 supporting files')
        db.add(SAPAttachment(proposal_id=proposal.id, revision_no=proposal.revision_no + 1, category=category,
            display_name=name[:150], file_name=name, content_type=content_type, storage_ref=ref,
            sha256=hashlib.sha256(data).hexdigest(), uploaded_by=owner_id))
        return sap.save(db, event, proposal, user, 'sap_attachment_uploaded', details={'category': category})
    except Exception:
        db.rollback()
        _cleanup_upload(db, ref)
        raise


@router.get('/attachments', response_model=list[SAPAttachmentOut], response_model_exclude_unset=True)
def list_attachments(event_id: UUID, revision_no: int | None = Query(None, ge=1), db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    _, proposal = sap.load(db, event_id, user)
    rev_no = revision_no or (proposal.revision_no + 1 if proposal.state in {'draft', 'revision_requested'} else proposal.revision_no)
    rows = db.query(SAPAttachment).filter_by(proposal_id=proposal.id, revision_no=rev_no).order_by(SAPAttachment.uploaded_at).all()
    return [{'id': str(row.id), 'category': row.category, 'display_name': row.display_name, 'file_name': row.file_name,
             'content_type': row.content_type, 'sha256': row.sha256, 'uploaded_at': row.uploaded_at.isoformat()} for row in rows]


@router.get('/attachments/{attachment_id}/download', response_model=SAPDownloadOut, response_model_exclude_unset=True)
def attachment_download(event_id: UUID, attachment_id: UUID, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    _, proposal = sap.load(db, event_id, user)
    row = db.query(SAPAttachment).filter_by(id=attachment_id, proposal_id=proposal.id).first()
    if row is None:
        raise HTTPException(404, 'Attachment not found')
    try:
        return {'url': storage.signed_file_url(row.storage_ref), 'expires_in': storage.SIGNED_URL_SECONDS, 'sha256': row.sha256}
    except (storage.StorageError, RuntimeError):
        raise HTTPException(503, 'Private storage is unavailable') from None


@router.put('/sds-review', response_model=SAPProposalOut, response_model_exclude_unset=True)
def review_notes(event_id: UUID, payload: ReviewNotesWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, payload.expected_version)
    if proposal.state != 'pending_sap_review':
        raise HTTPException(409, 'Only a pending revision can receive SDS remarks')
    rev = sap.revision(db, proposal)
    row = db.query(SAPReview).filter_by(revision_id=rev.id).first()
    if row is None:
        row = SAPReview(revision_id=rev.id, overall_remarks=payload.overall_remarks, section_remarks=payload.section_remarks)
        db.add(row)
    elif row.signed_at:
        raise HTTPException(409, 'Signed review is immutable; create a new revision')
    else:
        row.overall_remarks, row.section_remarks = payload.overall_remarks, payload.section_remarks
    return sap.save(db, event, proposal, user, 'sap_review_notes_saved')


@router.post('/sds-sign', response_model=SAPProposalOut, response_model_exclude_unset=True)
def sign_revision(event_id: UUID, payload: SDSReviewWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, payload.expected_version)
    if proposal.state != 'pending_sap_review':
        raise HTTPException(409, 'Only a pending revision can be signed')
    rev = sap.revision(db, proposal)
    row = db.query(SAPReview).filter_by(revision_id=rev.id).first()
    if row and row.signed_at:
        raise HTTPException(409, 'This revision is already signed')
    snapshot = _with_clearance(rev, proposal)
    if not snapshot['clearance']:
        raise HTTPException(422, 'Complete Part 4 before signing')
    try:
        validate_clearance(snapshot['clearance'], snapshot['collections'])
    except ValueError as exc:
        raise HTTPException(422, f'Complete Part 4 before signing: {exc}') from None
    overall = payload.overall_remarks if 'overall_remarks' in payload.model_fields_set else (row.overall_remarks if row else '')
    sections = payload.section_remarks if 'section_remarks' in payload.model_fields_set else (row.section_remarks if row else {})
    signer = user.full_name.strip() or user.email
    signed_pdf = render_proposal(snapshot, rev.revision_no, settings.sap_verification_base_url.rstrip('/') + '/' + rev.verification_token if settings.sap_verification_base_url else None, review={'overall_remarks': overall, 'section_remarks': sections},
        signer_name=signer, signature_strokes=payload.signature_strokes, signed=True)
    if row is None:
        row = SAPReview(revision_id=rev.id)
        db.add(row)
    row.overall_remarks, row.section_remarks = overall, sections
    row.signature_strokes, row.signed_by, row.signed_at = payload.signature_strokes, user.id, sap.now()
    row.signed_pdf, row.signed_pdf_sha256 = signed_pdf, hashlib.sha256(signed_pdf).hexdigest()
    proposal.state = 'sds_signed'
    return sap.save(db, event, proposal, user, 'sap_revision_signed', notify=True)


@router.post('/revise', response_model=SAPProposalOut, response_model_exclude_unset=True)
def revise_signed(event_id: UUID, payload: ReturnWrite, db: Session = Depends(get_db),
                  user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, payload.expected_version)
    if proposal.state != 'sds_signed':
        raise HTTPException(409, 'Only an SDS-signed proposal awaiting paper approval can start a correction')
    proposal.state, proposal.return_remarks, proposal.returned_by, proposal.clearance = 'revision_requested', payload.remarks, 'sds', None
    event.status = 'draft'
    return sap.save(db, event, proposal, user, 'sap_signed_revision_correction_requested', notify=True)


@router.put('/sds-clearance', response_model=SAPProposalOut, response_model_exclude_unset=True)
def clearance(event_id: UUID, payload: ClearanceWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, payload.expected_version)
    # Part 4 is filled in while reviewing what was sent, up until signing.
    if proposal.state not in {'draft', 'revision_requested', 'pending_sap_review'}:
        raise HTTPException(409, 'Part 4 can no longer change once the revision is signed')
    proposal.clearance = payload.clearance.model_dump(mode='json')
    return sap.save(db, event, proposal, user, 'sap_clearance_updated')


@router.post('/submit', response_model=SAPProposalOut, response_model_exclude_unset=True)
def submit(event_id: UUID, payload: Version, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, proposer=True, owner=True)
    sap.check_version(proposal, payload.expected_version, editable=True)
    if not settings.sap_verification_base_url:
        raise HTTPException(503, 'Configure SAP_VERIFICATION_BASE_URL before issuing controlled copies')
    return sap.submit(db, event, proposal, user, settings.sap_verification_base_url)


@router.post('/withdraw', response_model=SAPProposalOut, response_model_exclude_unset=True)
def withdraw(event_id: UUID, payload: Version, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, proposer=True, owner=True)
    sap.check_version(proposal, payload.expected_version)
    return sap.withdraw(db, event, proposal, user)


@router.get('/workflow', response_model=SAPWorkflowOut, response_model_exclude_unset=True)
def workflow(event_id: UUID, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    _, proposal = sap.load(db, event_id, user)
    return sap.workflow(db, proposal)


@router.post('/workflow/{step_id}/record', response_model=SAPWorkflowOut, response_model_exclude_unset=True)
def record(event_id: UUID, step_id: UUID, payload: CheckpointWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, payload.expected_version)
    if proposal.state not in {'pending_sap_review', 'sds_signed'}:
        raise HTTPException(409, 'Only the current reviewed revision can receive checkpoints')
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


@router.post('/return', response_model=SAPProposalOut, response_model_exclude_unset=True)
def return_proposal(event_id: UUID, payload: DecisionWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, payload.expected_version)
    if proposal.state != 'pending_sap_review':
        raise HTTPException(409, 'Only an unsigned pending SAP revision can be returned')
    _record_remarks(db, sap.revision(db, proposal), payload)
    proposal.state, proposal.return_remarks, proposal.returned_by, proposal.clearance = 'revision_requested', payload.remarks, 'sds', None
    event.status = 'draft'
    return sap.save(db, event, proposal, user, 'sap_returned', notify=True, details={'revision': proposal.revision_no, 'remarks': payload.remarks})


@router.post('/sds-reject', response_model=SAPProposalOut, response_model_exclude_unset=True)
def reject_proposal(event_id: UUID, payload: DecisionWrite, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    event, proposal = sap.load(db, event_id, user, write=True, sds=True)
    sap.check_version(proposal, payload.expected_version)
    if proposal.state != 'pending_sap_review':
        raise HTTPException(409, 'Only a pending revision can be rejected')
    _record_remarks(db, sap.revision(db, proposal), payload)
    proposal.state, event.status = 'rejected', 'rejected'  # final; a rejection is not a return, so return_remarks and returned_by stay
    return sap.save(db, event, proposal, user, 'sap_rejected', notify=True, details={'revision': proposal.revision_no, 'remarks': payload.remarks})


@router.get('/pdf', response_class=Response, responses={200: {'content': {'application/pdf': {'schema': {'type': 'string', 'format': 'binary'}}}}})
def pdf(event_id: UUID, revision_no: int | None = Query(None, ge=1), draft: bool = False, db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    _, proposal = sap.load(db, event_id, user)
    if draft and (revision_no or proposal.state not in {'draft', 'revision_requested'}):
        raise HTTPException(422, 'Draft preview requires an editable proposal and no revision number')
    if revision_no or (proposal.revision_no and not draft) or proposal.state not in {'draft', 'revision_requested'}:
        rev = sap.revision(db, proposal, revision_no)
        signed_review = db.query(SAPReview).filter_by(revision_id=rev.id).first()
        data = signed_review.signed_pdf if signed_review and signed_review.signed_pdf else _printout(proposal, rev.revision_no, lambda: render_proposal(_with_clearance(rev, proposal), rev.revision_no, settings.sap_verification_base_url.rstrip('/') + '/' + rev.verification_token if settings.sap_verification_base_url else None, review={'overall_remarks': signed_review.overall_remarks, 'section_remarks': signed_review.section_remarks} if signed_review else None, rejected=proposal.state == 'rejected' and rev.revision_no == proposal.revision_no))
        number = rev.revision_no
    else:
        try:
            Details.model_validate(proposal.details)
            data, number = _printout(proposal, 'draft', lambda: render_proposal(sap.snapshot(db, proposal), 'DRAFT')), 'draft'
        except ValueError as exc:
            raise HTTPException(422, str(exc)) from None
    return Response(data, media_type='application/pdf', headers={'Content-Disposition': f'attachment; filename="SAP-{event_id}-r{number}.pdf"', 'Cache-Control': 'private, no-store'})


@router.post('/final-signed-copy', status_code=201, response_model=SAPProposalOut, response_model_exclude_unset=True)
def final_copy(event_id: UUID, expected_version: int = Form(..., ge=1), file: UploadFile = File(...), db: Session = Depends(get_db), user: User = Depends(require_active_account)):
    if user.role != 'sds_staff':
        raise HTTPException(403, 'Only SDS staff may upload physical signature evidence')
    # Read bounded bytes before holding the event row lock during validation/upload.
    data = file.file.read(storage.MAX_UPLOAD_BYTES + 1)
    if not data or len(data) > storage.MAX_UPLOAD_BYTES or not data.startswith(b'%PDF-'):
        raise HTTPException(422, 'Upload a PDF of at most 10 MB')
    from pypdf import PdfReader
    try:
        reader = PdfReader(BytesIO(data), strict=True)
        if reader.is_encrypted or len(reader.pages) < 3:
            raise ValueError('Expected an unencrypted official form scan')
        root = reader.trailer['/Root']
        if '/OpenAction' in root or '/AA' in root or '/AcroForm' in root or '/Names' in root or any('/Annots' in p or '/AA' in p for p in reader.pages):
            raise ValueError('Upload a flattened scan without active content or attachments')
    except Exception:
        raise HTTPException(422, 'Expected a valid, flattened official form PDF scan without active content') from None
    event, proposal = sap.load(db, event_id, user, sds=True)
    sap.check_version(proposal, expected_version)
    if proposal.state != 'sds_signed':
        raise HTTPException(409, 'Final scan can only approve the SDS-signed revision')
    rev = sap.revision(db, proposal)
    rows = sap.steps(db, rev)
    if len(rows) != 9 or any(not row.evidence for row in rows):
        raise HTTPException(409, 'Record all nine physical signature checkpoints first')
    review = db.get(SAPReview, rev.id)
    if not review or not review.signed_pdf or len(reader.pages) != len(PdfReader(BytesIO(review.signed_pdf)).pages):
        raise HTTPException(422, 'Include every page of the SDS-signed form and its addenda in the scan')
    require_pre_activity_clearance(db, event)
    owner_id, organization_id = user.id, event.organization_id
    db.rollback()
    try:
        ref = storage.upload_proposal_letter(data, 'application/pdf', 'pdf', owner_id, organization_id)
    except (storage.StorageError, RuntimeError):
        raise HTTPException(503, 'Private storage is unavailable; no approval was recorded') from None
    try:
        event, proposal = sap.load(db, event_id, user, write=True, sds=True)
        sap.check_version(proposal, expected_version)
        if proposal.state != 'sds_signed' or event.organization_id != organization_id:
            raise HTTPException(409, 'Proposal changed; reload before uploading')
        require_pre_activity_clearance(db, event)
        rev = sap.revision(db, proposal)
        db.add(SAPFinalCopy(revision_id=rev.id, storage_ref=ref, sha256=hashlib.sha256(data).hexdigest(), uploaded_by=owner_id))
        proposal.state, event.status = 'approved', 'approved'
        return sap.save(db, event, proposal, user, 'sap_approved_with_physical_evidence', notify=True)
    except Exception:
        db.rollback()
        _cleanup_upload(db, ref)
        raise


@router.get('/final-signed-copy', response_model=SAPDownloadOut, response_model_exclude_unset=True)
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


@router.post('/evaluation', response_model=SAPProposalOut, response_model_exclude_unset=True)
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


@router.put('/{collection}', response_model=SAPProposalOut, response_model_exclude_unset=True)
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


@public_router.get('/sap/verify/{token}', response_model=SAPVerificationOut)
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
