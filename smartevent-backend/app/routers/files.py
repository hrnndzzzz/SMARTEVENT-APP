"""Issue short-lived file links only after authorizing the stored reference."""

from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.dependencies import (
    FINANCIAL_ROLES, require_active_account, require_operational_read,
    require_proposal_letter_reader, scope_query_by_department,
)
from app.models import Event, EventProposalLetter, Expense, Receipt, User
from app.services.storage import (
    SIGNED_URL_SECONDS, StorageError, canonical_file_url, signed_file_url, storage_object,
)
from app.services.event_routing import scope_event_query

router = APIRouter(prefix="/files", tags=["files"])


def _has_reference(query, column, reference, bucket, filename):
    candidates = query.filter(or_(
        column.contains(filename, autoescape=True),
        column.contains(quote(filename, safe=""), autoescape=True),
    )).with_entities(column)
    for (stored_reference,) in candidates.yield_per(100):
        try:
            if canonical_file_url(stored_reference, bucket) == reference:
                return True
        except ValueError:
            continue
    return False


def _authorize_receipt(db, user, reference, path):
    require_operational_read(user)
    parts = path.split("/")
    if (user.role in FINANCIAL_ROLES and len(parts) == 3 and parts[1] == str(user.id)
            and (user.role == "super_admin" or parts[0] == str(user.organization_id))):
        return
    for model in (Receipt, Expense):
        query = scope_query_by_department(db.query(model), model.department_id, user)
        if _has_reference(query, model.receipt_url, reference, settings.supabase_receipts_bucket, parts[-1]):
            return
    raise HTTPException(404, "File reference not found")


@router.get("")
def get_file_access(
    reference: str = Query(min_length=1, max_length=2048),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_active_account),
):
    try:
        obj = storage_object(reference)
        if obj is None:
            raise ValueError
        bucket, path = obj
        reference = canonical_file_url(reference, bucket)
    except ValueError:
        raise HTTPException(422, "Use a valid private storage reference") from None

    if bucket == settings.supabase_receipts_bucket:
        _authorize_receipt(db, current_user, reference, path)
    else:
        require_proposal_letter_reader(current_user)
        query = db.query(EventProposalLetter).join(Event, Event.id == EventProposalLetter.event_id)
        if current_user.role not in {"sds_staff", "super_admin"}:
            query = scope_event_query(query, db, current_user)
        if current_user.role == "officer":
            query = query.filter(Event.proposed_by == current_user.id)
        if not _has_reference(query, EventProposalLetter.document_url, reference, bucket, path.split("/")[-1]):
            raise HTTPException(404, "File reference not found")

    try:
        return {"url": signed_file_url(reference, bucket), "expires_in": SIGNED_URL_SECONDS}
    except RuntimeError:
        raise HTTPException(503, "File storage is not configured") from None
    except StorageError:
        raise HTTPException(502, "File access is temporarily unavailable") from None
