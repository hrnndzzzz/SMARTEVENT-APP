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
    remaining_budget only ever changes via the database trigger
    (fn_deduct_category_balance), which fires when status flips to
    'approved' — this router never sets remaining_budget directly.
    But nothing stops that trigger from running the category negative
    if two big expenses land back-to-back. So before approving, this
    router checks expense.amount against category.remaining_budget
    itself and blocks the approval with a 409 if it would overdraw the
    category. This is a belt-and-suspenders check on top of the
    trigger, not a replacement for it — the trigger is still what
    actually performs the deduction.

Access rules:
  - Anyone logged in can VIEW expenses.
  - The user who recorded an expense (or an admin) can edit/delete it
    while it's still pending.
  - Only advisers/admins can approve or reject a pending expense.
"""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, require_role
from app.models import Approval, Category, Expense, User
from app.schemas import (
    ApprovalDecision,
    ApprovalOut,
    ExpenseCreate,
    ExpenseOut,
    ExpenseUpdate,
    ReceiptParseRequest,
    ScanReceiptResponse,
)
from app.services.ocr import ReceiptParseError, parse_receipt_image, parse_receipt_text
from app.services.storage import StorageError, prepare_image_for_upload, upload_receipt_image

router = APIRouter(prefix="/expenses", tags=["expenses"])


def _get_expense_or_404(db: Session, expense_id: uuid.UUID) -> Expense:
    expense = db.query(Expense).filter(Expense.id == expense_id).first()
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


def _assert_owner_or_admin(expense: Expense, current_user: User, action: str) -> None:
    if expense.recorded_by != current_user.id and current_user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"You can only {action} expenses you recorded",
        )


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
    current_user: User = Depends(get_current_user),
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
    current_user: User = Depends(get_current_user),
):
    _get_category_or_400(db, payload.category_id)

    expense = Expense(
        event_id=payload.event_id,
        category_id=payload.category_id,
        description=payload.description,
        amount=payload.amount,
        receipt_url=payload.receipt_url,
        recorded_by=current_user.id,
        status="pending",
    )
    db.add(expense)
    db.commit()
    db.refresh(expense)
    return expense


@router.get("", response_model=list[ExpenseOut])
def list_expenses(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return db.query(Expense).order_by(Expense.created_at.desc()).all()


@router.get("/{expense_id}", response_model=ExpenseOut)
def get_expense(
    expense_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_expense_or_404(db, expense_id)


@router.get("/{expense_id}/approvals", response_model=list[ApprovalOut])
def list_expense_approvals(
    expense_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _get_expense_or_404(db, expense_id)
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
    current_user: User = Depends(get_current_user),
):
    expense = _get_expense_or_404(db, expense_id)
    _assert_owner_or_admin(expense, current_user, "edit")

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only pending expenses can be edited",
        )

    updates = payload.model_dump(exclude_unset=True)

    if "category_id" in updates:
        _get_category_or_400(db, updates["category_id"])

    for field, value in updates.items():
        setattr(expense, field, value)

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
    expense = _get_expense_or_404(db, expense_id)

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Expense is '{expense.status}' — only pending expenses can be approved",
        )

    category = db.query(Category).filter(Category.id == expense.category_id).first()
    if category is None:
        # Shouldn't happen (category_id is validated on create), but the
        # category could theoretically be deleted between then and now.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This expense's category no longer exists",
        )

    if expense.amount > category.remaining_budget:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"Approving this expense (₱{expense.amount:,.2f}) would exceed the "
                f"remaining budget for '{category.name}' (₱{category.remaining_budget:,.2f})"
            ),
        )

    _record_decision(db, expense, "approved", current_user, payload.remarks)
    expense.status = "approved"  # DB trigger deducts category.remaining_budget on this flip
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
    current_user: User = Depends(get_current_user),
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
    _assert_owner_or_admin(expense, current_user, "attach a receipt to")

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

    expense.receipt_url = receipt_url
    db.commit()
    db.refresh(expense)
    return expense


@router.post("/{expense_id}/parse-receipt", response_model=ExpenseOut)
def parse_receipt(
    expense_id: uuid.UUID,
    payload: ReceiptParseRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
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
    _assert_owner_or_admin(expense, current_user, "attach a receipt scan to")

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
    current_user: User = Depends(get_current_user),
):
    expense = _get_expense_or_404(db, expense_id)
    _assert_owner_or_admin(expense, current_user, "delete")

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only pending expenses can be deleted",
        )

    db.delete(expense)
    db.commit()
    return None