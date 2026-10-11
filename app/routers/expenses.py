"""
CRUD + approval workflow for expenses, following the same shape as
events.py. Reuses the `approvals` table (entity_type="expense") for
the same review-timeline pattern.

Status flow:
    pending --approve--> approved   (DB trigger deducts category budget)
              \\--reject--> rejected

There's no "draft" state for expenses — an expense is created once
money has actually been spent and someone is recording/claiming it, so
it starts straight at "pending" and goes to a reviewer from there.

Budget check on approval:
    remaining_budget (on both the expense's category AND, if set, its
    event) only ever changes via database triggers
    (fn_deduct_category_balance / fn_deduct_event_budget), which fire
    when status flips to 'approved' — this router never sets either
    remaining_budget directly. But nothing stops those triggers from
    running a category or event negative if two big expenses land
    back-to-back. So before approving, this router checks
    expense.amount against BOTH category.remaining_budget and (when
    expense.event_id is set) event.remaining_budget, and blocks with a
    409 if either would be overdrawn. This is a belt-and-suspenders
    check on top of the triggers, not a replacement for them — the
    triggers are still what actually perform the deductions.

Access rules:
    - Super Admin sees all expenses; admins, advisers, treasurers, and
        officers see only expenses in their own department.
  - The Treasurer who recorded an expense (or an admin) can edit/delete
    it while it's still pending.
  - Only advisers/admins can approve or reject a pending expense.
  - The submitter cannot approve or reject their own expense.
"""

import uuid
import hashlib
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import (
    assert_department_scope,
    assert_record_scope,
    assert_not_self_review,
    assert_owner_or_admin,
    require_financial_access,
    require_operational_read,
    require_role,
    resolve_department_id,
    resolve_organization_id,
    scope_query_by_department,
)
from app.models import (
    Approval,
    Category,
    Event,
    Expense,
    ExpenseItem,
    Receipt,
    User,
)
from app.schemas import (
    ApprovalDecision,
    ApprovalOut,
    ExpenseCreate,
    ExpenseItemOut,
    ExpenseOut,
    ExpenseUpdate,
    ReceiptParseRequest,
    ScanReceiptResponse,
    PurchaseCompletion,
)
from app.services.purchase_completion import complete_purchase
from app.services.ocr import ReceiptParseError, parse_receipt_image, parse_receipt_text
from app.services.storage import StorageError, prepare_image_for_upload, upload_receipt_image
from app.services.receipt_validation import sync_expense_receipt, assert_receipt_review_complete, receipt_for_transaction

router = APIRouter(prefix="/expenses", tags=["expenses"])


def _get_expense_or_404(db: Session, expense_id: uuid.UUID) -> Expense:
    expense = db.query(Expense).filter(Expense.id == expense_id).with_for_update().first()
    if expense is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Expense not found")
    return expense


def _get_category_or_400(db: Session, category_id: uuid.UUID) -> Category:
    # A FK violation from the DB would also catch a bad category_id, but
    # that surfaces as an ugly 500 (as you saw with events). Checking
    # here first gives a clean 400 instead.
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="category_id does not match any existing category",
        )
    return category


def _assert_expense_owner_scope(
    expense: Expense,
    db: Session,
    current_user: User,
    action: str,
    *,
    owner_roles: set[str] = {"treasurer"},
) -> None:
    assert_owner_or_admin(expense.recorded_by, current_user, action, owner_roles=owner_roles)
    assert_record_scope(current_user, expense)


def _next_step_order(db: Session, expense_id: uuid.UUID) -> int:
    count = (
        db.query(Approval)
        .filter(Approval.entity_type == "expense", Approval.entity_id == expense_id)
        .count()
    )
    return count + 1


def _record_decision(
    db: Session,
    expense: Expense,
    decision: str,
    reviewer: User,
    remarks: str | None,
) -> None:
    approval = Approval(
        entity_type="expense",
        entity_id=expense.id,
        step_order=_next_step_order(db, expense.id),
        reviewer_id=reviewer.id,
        decision=decision,
        remarks=remarks,
        decided_at=datetime.now(timezone.utc),
    )
    db.add(approval)


# NOTE: this route must be declared before any "/{expense_id}..." route
# below, or FastAPI will try to parse "scan-receipt" as a UUID for
# expense_id and return 422 instead of reaching this handler — same
# gotcha as GET /inventory/low-stock in inventory.py.
@router.post("/scan-receipt", response_model=ScanReceiptResponse, status_code=status.HTTP_200_OK)
async def scan_receipt(
    file: UploadFile = File(...),
    current_user: User = Depends(require_financial_access),
):
    """
    "Snap first, fill later": takes a receipt photo BEFORE any Expense
    exists, uploads it to Storage, and asks Gemini Vision to read it —
    merchant, date, total, and itemized line items (each tagged
    asset/consumable). Returns that data directly; nothing is written
    to the database here, not even an Expense row.

    The officer reviews/corrects the returned fields in the app, then
    calls POST /expenses separately with the final values — referencing
    the receipt_url this endpoint already uploaded, so the photo isn't
    lost even if they abandon the form partway through.

    This is the image-based counterpart to POST /expenses/{id}/parse-receipt,
    which stays in place for the text-based (ML Kit) flow — see the
    module docstring in app/services/ocr.py for why both exist.
    """
    allowed_types = {"image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic"}
    if file.content_type not in allowed_types:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Unsupported file type '{file.content_type}'. "
                f"Allowed: {', '.join(sorted(allowed_types))}"
            ),
        )

    raw_bytes = await file.read()

    max_size_bytes = 10 * 1024 * 1024  # 10MB
    if len(raw_bytes) > max_size_bytes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File too large. Maximum size is 10MB",
        )

    try:
        processed_bytes, content_type = prepare_image_for_upload(raw_bytes)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not process the uploaded image: {exc}",
        )

    try:
        receipt_url = upload_receipt_image(processed_bytes, content_type)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))
    except StorageError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc))

    try:
        parsed = parse_receipt_image(processed_bytes, content_type)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))
    except ReceiptParseError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Could not reach the receipt parsing service: {exc}",
        )

    return ScanReceiptResponse(
        receipt_url=receipt_url,
        merchant=parsed["merchant"],
        date=parsed["date"],
        amount=parsed["amount"],
        items=parsed["items"],
    )


@router.post("", response_model=ExpenseOut, status_code=status.HTTP_201_CREATED)
def create_expense(
    payload: ExpenseCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_financial_access),
):
    category = _get_category_or_400(db, payload.category_id)
    assert_record_scope(current_user, category)

    event = None
    if payload.event_id is not None:
        event = db.query(Event).filter(Event.id == payload.event_id).first()
        if event is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="event_id does not match any existing event")
        assert_record_scope(current_user, event)

    requested_department_id = (
        payload.department_id
        or category.department_id
        or (event.department_id if event is not None else None)
    )
    department_id = resolve_department_id(
        current_user,
        requested_department_id,
        require_for_admin=True,
    )
    if category.department_id != department_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Expense department must match the selected category department",
        )
    if event is not None and event.department_id != department_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Expense department must match the selected event department",
        )

    organization_id = resolve_organization_id(
        db, current_user, payload.organization_id or category.organization_id, department_id
    )
    if category.organization_id != organization_id or (event is not None and event.organization_id != organization_id):
        raise HTTPException(status_code=400, detail="Expense, category, and event must share an organization")

    if payload.receipt and payload.receipt_url and str(payload.receipt.receipt_url) != str(payload.receipt_url):
        raise HTTPException(422, "receipt_url and receipt.receipt_url must match")
    expense = Expense(
        organization_id=organization_id,
        department_id=department_id,
        event_id=payload.event_id,
        category_id=payload.category_id,
        description=payload.description,
        amount=payload.amount,
        expense_date=payload.expense_date,
        receipt_url=str(payload.receipt_url) if payload.receipt_url else None,
        recorded_by=current_user.id,
        status="pending",
    )
    db.add(expense)
    db.flush()  # assigns expense.id without committing, so the items
                # below can reference it in the same commit

    for item in payload.items:
        db.add(
            ExpenseItem(
                expense_id=expense.id,
                name=item.name,
                amount=item.amount,
                category=item.category,
                quantity=item.quantity,
                unit=item.unit,
            )
        )

    sync_expense_receipt(db, expense, current_user, payload.receipt)
    db.commit()
    db.refresh(expense)
    return expense


@router.get("/{expense_id}/items", response_model=list[ExpenseItemOut])
def list_expense_items(
    expense_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    expense = _get_expense_or_404(db, expense_id)
    assert_record_scope(current_user, expense, allow_officer_read=True)
    return (
        db.query(ExpenseItem)
        .filter(ExpenseItem.expense_id == expense_id)
        .order_by(ExpenseItem.created_at)
        .all()
    )


@router.get("", response_model=list[ExpenseOut])
def list_expenses(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    query = scope_query_by_department(db.query(Expense), Expense.department_id, current_user)
    return query.order_by(Expense.created_at.desc()).all()


@router.get("/{expense_id}", response_model=ExpenseOut)
def get_expense(
    expense_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    expense = _get_expense_or_404(db, expense_id)
    assert_record_scope(current_user, expense, allow_officer_read=True)
    return expense


@router.get("/{expense_id}/approvals", response_model=list[ApprovalOut])
def list_expense_approvals(
    expense_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    expense = _get_expense_or_404(db, expense_id)
    assert_record_scope(current_user, expense, allow_officer_read=True)
    return (
        db.query(Approval)
        .filter(Approval.entity_type == "expense", Approval.entity_id == expense_id)
        .order_by(Approval.step_order)
        .all()
    )


@router.patch("/{expense_id}", response_model=ExpenseOut)
def update_expense(
    expense_id: uuid.UUID,
    payload: ExpenseUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("treasurer", "admin")),
):
    expense = _get_expense_or_404(db, expense_id)
    _assert_expense_owner_scope(expense, db, current_user, "edit")

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only pending expenses can be edited",
        )

    updates = payload.model_dump(exclude_unset=True)
    recorded_receipt = receipt_for_transaction(db, expense)
    if recorded_receipt:
        for field in ("event_id", "amount", "expense_date"):
            if field in updates and updates[field] != getattr(expense, field):
                raise HTTPException(409, "Event, amount, and date are immutable after a receipt is recorded")
    if "receipt_url" in updates:
        if updates["receipt_url"] is None and receipt_for_transaction(db, expense):
            raise HTTPException(409, "A recorded receipt cannot be detached")
        if updates["receipt_url"] is not None:
            updates["receipt_url"] = str(updates["receipt_url"])

    if "department_id" in updates:
        if updates["department_id"] != expense.department_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only admins can change an expense's department scope",
            )
        updates["department_id"] = resolve_department_id(
            current_user,
            updates["department_id"],
            require_for_admin=True,
        )

    category = db.query(Category).filter(Category.id == expense.category_id).first()
    if "category_id" in updates:
        category = _get_category_or_400(db, updates["category_id"])
        assert_record_scope(current_user, category)

    event = None
    if "event_id" in updates and updates["event_id"] is not None:
        event = db.query(Event).filter(Event.id == updates["event_id"]).first()
        if event is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="event_id does not match any existing event")
        assert_record_scope(current_user, event)

    if category is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This expense's category no longer exists",
        )
    target_department_id = updates.get("department_id", expense.department_id)
    if category.department_id != target_department_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Expense department must match the selected category department",
        )
    if event is None and "event_id" not in updates and expense.event_id is not None:
        event = db.query(Event).filter(Event.id == expense.event_id).first()
    if event is not None and event.department_id != target_department_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Expense department must match the selected event department",
        )

    if category.organization_id != expense.organization_id or (event is not None and event.organization_id != expense.organization_id):
        raise HTTPException(status_code=400, detail="Expense, category, and event must share an organization")

    for field, value in updates.items():
        setattr(expense, field, value)
    sync_expense_receipt(db, expense, current_user)

    db.commit()
    db.refresh(expense)
    return expense


@router.post("/{expense_id}/approve", response_model=ExpenseOut)
def approve_expense(
    expense_id: uuid.UUID,
    payload: ApprovalDecision = ApprovalDecision(),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("adviser", "admin")),
):
    expense = db.query(Expense).filter(Expense.id == expense_id).with_for_update().first()
    if expense is None:
        raise HTTPException(404, "Expense not found")

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Expense is '{expense.status}' — only pending expenses can be approved",
        )

    assert_record_scope(current_user, expense)
    assert_not_self_review(expense.recorded_by, current_user)
    assert_receipt_review_complete(db, expense)
    if db.query(ExpenseItem).filter(ExpenseItem.expense_id == expense.id, ExpenseItem.category == "asset").first():
        if not db.query(Receipt).filter(Receipt.expense_id == expense.id).first():
            raise HTTPException(409, "Record the asset purchase receipt before submitting expense approval")

    category = db.query(Category).filter(Category.id == expense.category_id).with_for_update().first()
    if category is None:
        # Shouldn't happen (category_id is validated on create), but the
        # category could theoretically be deleted between then and now.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This expense's category no longer exists",
        )
    assert_record_scope(current_user, category)
    if category.department_id != expense.department_id or category.organization_id != expense.organization_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This expense's category belongs to a different department",
        )

    if expense.amount > category.remaining_budget:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"Approving this expense (₱{expense.amount:,.2f}) would exceed the "
                f"remaining budget for '{category.name}' (₱{category.remaining_budget:,.2f})"
            ),
        )

    # Same guard as the category check above, but for the event's own
    # allocated_budget — a separate, narrower pool than the category.
    # Not every expense is tied to an event (event_id is nullable), so
    # this only runs when one is set.
    if expense.event_id is not None:
        event = db.query(Event).filter(Event.id == expense.event_id).with_for_update().first()
        if event is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This expense's event no longer exists",
            )
        assert_record_scope(current_user, event)
        if event.department_id != expense.department_id or event.organization_id != expense.organization_id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This expense's event belongs to a different department",
            )
        if expense.amount > event.remaining_budget:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"Approving this expense (₱{expense.amount:,.2f}) would exceed the "
                    f"remaining budget for event '{event.title}' (₱{event.remaining_budget:,.2f})"
                ),
            )

    _record_decision(db, expense, "approved", current_user, payload.remarks)
    expense.status = "approved"  # DB triggers deduct category AND event remaining_budget on this flip
    db.commit()
    db.refresh(expense)
    return expense


@router.post("/{expense_id}/reject", response_model=ExpenseOut)
def reject_expense(
    expense_id: uuid.UUID,
    payload: ApprovalDecision = ApprovalDecision(),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("adviser", "admin")),
):
    expense = _get_expense_or_404(db, expense_id)

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Expense is '{expense.status}' — only pending expenses can be rejected",
        )

    assert_record_scope(current_user, expense)
    assert_not_self_review(expense.recorded_by, current_user)

    _record_decision(db, expense, "rejected", current_user, payload.remarks)
    expense.status = "rejected"
    db.commit()
    db.refresh(expense)
    return expense


@router.post("/{expense_id}/receipt", response_model=ExpenseOut)
async def upload_receipt(
    expense_id: uuid.UUID,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("treasurer", "admin")),
):
    """
    Uploads a receipt photo to Supabase Storage and saves the resulting
    URL onto this expense's receipt_url.

    This is separate from POST .../parse-receipt: this route stores the
    photo itself, parse-receipt turns OCR text (extracted from that
    photo on the phone, by ML Kit) into structured fields. They can be
    called in either order, but uploading the photo first is the
    natural flow.
    """
    expense = _get_expense_or_404(db, expense_id)
    _assert_expense_owner_scope(expense, db, current_user, "attach a receipt to")

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only pending expenses can have a receipt attached",
        )

    allowed_types = {"image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic"}
    if file.content_type not in allowed_types:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Unsupported file type '{file.content_type}'. "
                f"Allowed: {', '.join(sorted(allowed_types))}"
            ),
        )

    raw_bytes = await file.read(10 * 1024 * 1024 + 1)

    max_size_bytes = 10 * 1024 * 1024  # 10MB
    if len(raw_bytes) > max_size_bytes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File too large. Maximum size is 10MB",
        )

    try:
        processed_bytes, content_type = prepare_image_for_upload(raw_bytes)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Could not process the uploaded image: {exc}",
        )

    try:
        receipt_url = upload_receipt_image(processed_bytes, content_type)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))
    except StorageError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc))

    expense.receipt_url = receipt_url
    sync_expense_receipt(db, expense, current_user, file_sha256=hashlib.sha256(raw_bytes).hexdigest())
    db.commit()
    db.refresh(expense)
    return expense


@router.post("/{expense_id}/parse-receipt", response_model=ExpenseOut)
def parse_receipt(
    expense_id: uuid.UUID,
    payload: ReceiptParseRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("treasurer", "admin")),
):
    """
    Takes raw OCR text (already extracted on-device by the Flutter app)
    and asks Gemini to turn it into structured fields, saved onto this
    expense's ocr_merchant/ocr_date/ocr_amount.

    If the scanned total disagrees with the officer-entered `amount` by
    more than the tolerance below, the expense is auto-flagged — this is
    separate from (and happens earlier than) the over-budget check that
    runs at approval time.
    """
    expense = _get_expense_or_404(db, expense_id)
    _assert_expense_owner_scope(expense, db, current_user, "attach a receipt scan to")

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only pending expenses can have a receipt scan attached",
        )

    try:
        parsed = parse_receipt_text(payload.raw_text)
    except RuntimeError as exc:
        # Missing/misconfigured API key — an ops problem, not the
        # caller's fault, so 503 rather than 400/422.
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))
    except ReceiptParseError as exc:
        # Gemini responded but not in the shape we asked for.
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc))
    except Exception as exc:
        # Network/auth/rate-limit errors from the Gemini SDK itself.
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Could not reach the receipt parsing service: {exc}",
        )

    expense.ocr_merchant = parsed["merchant"]
    expense.ocr_date = parsed["date"]
    expense.ocr_amount = parsed["amount"]
    if expense.receipt_url:
        sync_expense_receipt(db, expense, current_user)

    if parsed["amount"] is not None:
        # Flag if the scanned total is off by more than ₱5 or 3%,
        # whichever is bigger — small OCR/rounding noise shouldn't flag,
        # a genuinely different amount should.
        tolerance = max(5.0, float(expense.amount) * 0.03)
        if abs(parsed["amount"] - float(expense.amount)) > tolerance:
            expense.is_flagged = True
            expense.flag_reason = (
                f"Scanned receipt total (₱{parsed['amount']:,.2f}) differs from "
                f"the entered amount (₱{expense.amount:,.2f}) by more than "
                f"expected"
            )
        else:
            expense.is_flagged = False
            expense.flag_reason = None

    db.commit()
    db.refresh(expense)
    return expense


@router.delete("/{expense_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_expense(
    expense_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("treasurer", "admin")),
):
    expense = _get_expense_or_404(db, expense_id)
    _assert_expense_owner_scope(expense, db, current_user, "delete")

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only pending expenses can be deleted",
        )

    if receipt_for_transaction(db, expense):
        raise HTTPException(409, "Expenses with recorded receipts must be rejected, not deleted")
    db.delete(expense)
    db.commit()
    return None


@router.post("/{expense_id}/complete-purchase", response_model=ExpenseOut)
def complete_expense_purchase(expense_id: uuid.UUID, payload: PurchaseCompletion,
                              db: Session = Depends(get_db),
                              current_user: User = Depends(require_financial_access)):
    expense = _get_expense_or_404(db, expense_id)
    return complete_purchase(db, expense, payload, current_user)
