"""Organization-scoped exact duplication and conservative similarity checks."""
from datetime import timedelta
from decimal import Decimal
import hashlib
import re
import unicodedata
from urllib.parse import urlsplit, urlunsplit
from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from app.config import settings
from app.dependencies import assert_record_scope
from app.models import Event, Expense, IncomeRecord, Organization, Receipt
from app.schemas import ReceiptDetails
from app.services.storage import canonical_file_url, storage_object


def normalized(value):
    return re.sub(r"\s+", " ", unicodedata.normalize("NFKC", value or "").strip().casefold())


def possible_duplicate_expenses(db, organization_id, names, amount, on, exclude_id=None):
    """Pending or approved expenses that look like the same purchase: same amount, a day apart, same name."""
    keys = {normalized(name) for name in names} - {""}
    if not keys or amount is None or on is None:
        return []
    query = db.query(Expense).filter(
        Expense.organization_id == organization_id,
        Expense.status.in_(["pending", "approved"]),
        Expense.amount == Decimal(str(amount)).quantize(Decimal("0.01")),
        Expense.expense_date >= on - timedelta(days=1),
        Expense.expense_date <= on + timedelta(days=1),
    )
    if exclude_id is not None:
        query = query.filter(Expense.id != exclude_id)
    return [row for row in query.order_by(Expense.created_at).all()
            if keys & {normalized(row.description), normalized(row.ocr_merchant)}]


def duplicate_note(rows):
    row = rows[0]
    return f"Possible duplicate of {row.description} ₱{Decimal(str(row.amount)):,.2f} on {row.expense_date.isoformat()}"


def fingerprint(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def url_key(url):
    parts = urlsplit(canonical_file_url(str(url), settings.supabase_receipts_bucket))
    return fingerprint(urlunsplit((parts.scheme.lower(), parts.netloc.lower(), parts.path, "", "")))


def _url_fingerprints(url):
    parts = urlsplit(url)
    paths = {parts.path}
    if storage_object(url, settings.supabase_receipts_bucket):
        prefix, object_path = parts.path.split("/storage/v1/object/", 1)
        paths.update(prefix + "/storage/v1/object/" + access + "/" + object_path
                     for access in ("public", "authenticated", "sign"))
    return [fingerprint(urlunsplit((parts.scheme.lower(), parts.netloc.lower(), path, "", ""))) for path in paths]


def receipt_for_transaction(db, transaction):
    field = Receipt.expense_id if isinstance(transaction, Expense) else Receipt.income_id
    return db.query(Receipt).filter(field == transaction.id).first()


def save_receipt(db, transaction, details, current_user, *, file_sha256=None, allow_historical=False):
    event = db.query(Event).filter(Event.id == transaction.event_id).first()
    if event is None:
        raise HTTPException(422, "Every receipt requires a transaction linked to an existing event")
    assert_record_scope(current_user, event, allow_officer_read=True)
    if not event.organization_id or not event.department_id:
        raise HTTPException(409, "Assign the event to an organization and department first")
    if isinstance(transaction, Expense):
        assert_record_scope(current_user, transaction, allow_officer_read=True)
        if transaction.status != "pending" and not (allow_historical and current_user.role == "super_admin"):
            raise HTTPException(409, "Only pending expenses can have receipt data changed")
    # Serialize matching checks for writes in the same organization.
    db.query(Organization).filter(Organization.id == event.organization_id).with_for_update().first()
    existing = receipt_for_transaction(db, transaction)
    if allow_historical and existing:
        raise HTTPException(409, "Historical import cannot replace an existing receipt")
    if existing and existing.review_status in {"cleared", "rejected"}:
        raise HTTPException(409, "Reviewed receipt evidence is immutable")
    try:
        receipt_url = canonical_file_url(str(details.receipt_url), settings.supabase_receipts_bucket)
        obj = storage_object(receipt_url, settings.supabase_receipts_bucket)
        old_url = existing.receipt_url if existing else None
        existing_link = old_url and canonical_file_url(old_url, settings.supabase_receipts_bucket) == receipt_url
    except ValueError:
        raise HTTPException(422, "Invalid receipt storage reference") from None
    if obj and not existing_link and not (allow_historical and current_user.role == "super_admin"):
        path = obj[1].split("/")
        if len(path) != 3 or path[:2] != [str(event.organization_id), str(current_user.id)]:
            raise HTTPException(403, "Only your own files uploaded for this organization can be attached")
    amount = details.amount if details.amount is not None else Decimal(str(transaction.amount))
    if amount != Decimal(str(transaction.amount)):
        raise HTTPException(422, "Receipt amount must match the linked transaction amount")
    merchant = normalized(details.merchant)
    number = normalized(details.receipt_number)
    reference_key = fingerprint(merchant + "\n" + number) if merchant and number else None
    url_fingerprint = url_key(receipt_url)
    query = db.query(Receipt).filter(Receipt.organization_id == event.organization_id)
    if existing:
        query = query.filter(Receipt.id != existing.id)
    # Recognize fingerprints stored before public URLs became canonical references.
    exact = [Receipt.url_fingerprint.in_(_url_fingerprints(receipt_url))]
    if file_sha256:
        exact.append(Receipt.file_sha256 == file_sha256)
    if reference_key:
        exact.append(Receipt.reference_key == reference_key)
    match = query.filter(or_(*exact)).first()
    if match:
        raise HTTPException(409, {"code": "duplicate_receipt", "detail": "Receipt URL, file, or merchant/reference is already recorded", "receipt_id": str(match.id)})
    # Legacy expense URLs also reserve their evidence before receipt import.
    legacy = db.query(Expense).filter(Expense.organization_id == event.organization_id,
        Expense.receipt_url.is_not(None))
    if isinstance(transaction, Expense):
        legacy = legacy.filter(Expense.id != transaction.id)
    if any(url_key(row.receipt_url) == url_fingerprint for row in legacy.all()):
        raise HTTPException(409, "Receipt URL is already attached to an existing expense")
    issued_on = details.issued_on or (transaction.expense_date if isinstance(transaction, Expense) else transaction.received_on)
    similar = []
    if merchant:
        candidates = query.filter(Receipt.amount == amount,
            Receipt.issued_on >= issued_on - timedelta(days=1),
            Receipt.issued_on <= issued_on + timedelta(days=1)).all()
        similar = [str(row.id) for row in candidates if normalized(row.merchant) == merchant]
    if existing and existing.review_status == "pending":
        similar = sorted(set(similar + existing.similar_receipt_ids))
    receipt = existing or Receipt(recorded_by=current_user.id)
    receipt.organization_id = event.organization_id
    receipt.department_id = event.department_id
    receipt.event_id = event.id
    receipt.expense_id = transaction.id if isinstance(transaction, Expense) else None
    receipt.income_id = transaction.id if isinstance(transaction, IncomeRecord) else None
    receipt.purpose = details.purpose
    receipt.receipt_url = receipt_url
    receipt.merchant = details.merchant
    receipt.receipt_number = details.receipt_number
    receipt.issued_on = issued_on
    receipt.amount = amount
    receipt.url_fingerprint = url_fingerprint
    receipt.file_sha256 = file_sha256
    receipt.reference_key = reference_key
    receipt.is_flagged = bool(similar)
    receipt.similar_receipt_ids = similar
    receipt.review_status = "pending" if similar else "clear"
    receipt.review_reason = None
    receipt.reviewed_by = None
    receipt.reviewed_at = None
    db.add(receipt)
    if isinstance(transaction, Expense):
        transaction.receipt_url = receipt.receipt_url
    else:
        transaction.receipt = receipt
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Receipt was concurrently recorded or conflicts with an existing receipt")
    return receipt


def sync_expense_receipt(db, expense, user, details=None, file_sha256=None):
    if not expense.receipt_url and details is None:
        return None
    old = receipt_for_transaction(db, expense)
    if details is None:
        from pydantic import ValidationError
        try:
            details = ReceiptDetails(receipt_url=expense.receipt_url, purpose=expense.description,
                merchant=expense.ocr_merchant or (old.merchant if old else None),
                receipt_number=old.receipt_number if old else None,
                issued_on=expense.ocr_date or expense.expense_date, amount=expense.amount)
        except ValidationError:
            raise HTTPException(409, "Correct invalid legacy receipt URL, purpose, or transaction amount first")
    return save_receipt(db, expense, details, user,
                        file_sha256=file_sha256 or (old.file_sha256 if old and url_key(old.receipt_url) == url_key(details.receipt_url) else None))


def assert_receipt_review_complete(db, expense):
    if db.query(Receipt).filter(Receipt.expense_id == expense.id, Receipt.review_status.in_(["pending", "rejected"])).first():
        raise HTTPException(409, "A similar receipt must be reviewed before expense approval")
