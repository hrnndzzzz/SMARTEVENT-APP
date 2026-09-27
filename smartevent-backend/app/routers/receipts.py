"""Receipts always refer to one financial transaction and its event."""
import hashlib
import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from sqlalchemy.orm import Session
from app.database import get_db
from app.dependencies import assert_not_self_review, assert_owner_or_admin, assert_record_scope, require_financial_access, require_operational_read, require_role, scope_query_by_department
from app.models import Event, Expense, IncomeRecord, Receipt, User
from app.schemas import ReceiptCreate, ReceiptDetails, ReceiptOut, ReceiptReview
from app.services.access_audit import record_access_change
from app.services.receipt_validation import save_receipt
from app.services.storage import prepare_image_for_upload, upload_receipt_image, StorageError

router = APIRouter(prefix="/receipts", tags=["receipts"])


def get_receipt(db, receipt_id, user, read=False):
    receipt = db.query(Receipt).filter(Receipt.id == receipt_id).first()
    if receipt is None:
        raise HTTPException(404, "Receipt not found")
    assert_record_scope(user, receipt, allow_officer_read=read)
    return receipt


def get_transaction(db, expense_id=None, income_id=None):
    model, id = (Expense, expense_id) if expense_id else (IncomeRecord, income_id)
    transaction = db.query(model).filter(model.id == id).with_for_update().first()
    if transaction is None:
        raise HTTPException(404, "Financial transaction not found")
    return transaction


@router.post("", response_model=ReceiptOut, status_code=201)
def create_receipt(payload: ReceiptCreate, db: Session = Depends(get_db),
                   current_user: User = Depends(require_financial_access)):
    transaction = get_transaction(db, payload.expense_id, payload.income_id)
    assert_owner_or_admin(transaction.recorded_by, current_user, "attach receipts", owner_roles={"treasurer"})
    details = ReceiptDetails(**payload.model_dump(exclude={"expense_id", "income_id"}))
    receipt = save_receipt(db, transaction, details, current_user)
    record_access_change(db, current_user, "receipt.recorded", receipt)
    db.commit()
    db.refresh(receipt)
    return receipt


@router.get("", response_model=list[ReceiptOut])
def list_receipts(event_id: uuid.UUID | None = None, flagged_only: bool = False,
                  review_status: str | None = Query(None, pattern="^(clear|pending|cleared|rejected)$"),
                  db: Session = Depends(get_db), current_user: User = Depends(require_operational_read)):
    query = scope_query_by_department(db.query(Receipt), Receipt.department_id, current_user)
    if event_id:
        query = query.filter(Receipt.event_id == event_id)
    if flagged_only:
        query = query.filter(Receipt.is_flagged.is_(True))
    if review_status:
        query = query.filter(Receipt.review_status == review_status)
    return query.order_by(Receipt.created_at.desc()).all()


@router.get("/{receipt_id}", response_model=ReceiptOut)
def read_receipt(receipt_id: uuid.UUID, db: Session = Depends(get_db), current_user: User = Depends(require_operational_read)):
    return get_receipt(db, receipt_id, current_user, read=True)


@router.post("/{receipt_id}/review", response_model=ReceiptOut)
def review_receipt(receipt_id: uuid.UUID, payload: ReceiptReview, db: Session = Depends(get_db),
                   current_user: User = Depends(require_role("adviser", "admin"))):
    receipt = db.query(Receipt).filter(Receipt.id == receipt_id).with_for_update().first()
    if receipt is None:
        raise HTTPException(404, "Receipt not found")
    assert_record_scope(current_user, receipt)
    assert_not_self_review(receipt.recorded_by, current_user)
    if receipt.review_status != "pending":
        raise HTTPException(409, "Only pending similar-receipt flags can be cleared")
    receipt.review_status = payload.decision
    receipt.review_reason = payload.reason
    receipt.reviewed_by = current_user.id
    receipt.reviewed_at = datetime.now(timezone.utc)
    record_access_change(db, current_user, "receipt.similarity_reviewed", receipt, {"reason": payload.reason, "decision": payload.decision})
    db.commit()
    db.refresh(receipt)
    return receipt


@router.post("/{receipt_id}/upload", response_model=ReceiptOut)
async def upload_receipt_file(receipt_id: uuid.UUID, file: UploadFile = File(...),
                              db: Session = Depends(get_db), current_user: User = Depends(require_financial_access)):
    receipt = get_receipt(db, receipt_id, current_user)
    transaction = get_transaction(db, receipt.expense_id, receipt.income_id)
    assert_owner_or_admin(transaction.recorded_by, current_user, "upload receipts", owner_roles={"treasurer"})
    if file.content_type not in {"image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic"}:
        raise HTTPException(400, "Upload a supported receipt image")
    raw = await file.read(10 * 1024 * 1024 + 1)
    if not raw or len(raw) > 10 * 1024 * 1024:
        raise HTTPException(400, "Receipt image must be between 1 byte and 10MB")
    digest = hashlib.sha256(raw).hexdigest()
    # Reject a known file before writing another storage object.
    if db.query(Receipt).filter(Receipt.organization_id == receipt.organization_id,
            Receipt.id != receipt.id, Receipt.file_sha256 == digest).first():
        raise HTTPException(409, "This receipt file has already been recorded")
    try:
        processed, content_type = prepare_image_for_upload(raw)
    except Exception:
        raise HTTPException(400, "Could not process receipt image")
    try:
        url = upload_receipt_image(processed, content_type)
    except RuntimeError as exc:
        raise HTTPException(503, str(exc))
    except StorageError:
        raise HTTPException(502, "Receipt storage upload failed")
    details = ReceiptDetails(receipt_url=url, purpose=receipt.purpose, merchant=receipt.merchant,
        receipt_number=receipt.receipt_number, issued_on=receipt.issued_on, amount=receipt.amount)
    receipt = save_receipt(db, transaction, details, current_user, file_sha256=digest)
    record_access_change(db, current_user, "receipt.file_uploaded", receipt)
    db.commit()
    db.refresh(receipt)
    return receipt
