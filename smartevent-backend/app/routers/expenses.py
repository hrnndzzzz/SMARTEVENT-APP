import uuid
import hashlib

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.config import settings
from app.dependencies import (
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
    Organization,
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
from app.services.approvals import record_decision
from app.services.ocr import ReceiptParseError, parse_receipt_image, parse_receipt_text
from app.services.storage import StorageError, canonical_file_url, prepare_image_for_upload, upload_receipt_image
from app.services.receipt_validation import sync_expense_receipt, assert_receipt_review_complete, receipt_for_transaction

router = APIRouter(prefix="/expenses", tags=["expenses"])


def _get_expense_or_404(db: Session, expense_id: uuid.UUID, *, lock: bool = False) -> Expense:
    query = db.query(Expense).filter(Expense.id == expense_id)
    if lock:
        query = query.with_for_update()
    expense = query.first()
    if expense is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Expense not found")
    return expense


def _get_category_or_400(db: Session, category_id: uuid.UUID) -> Category:
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="category_id does not match any existing category",
        )
    return category


def _assert_expense_owner_scope(
    expense: Expense,
    current_user: User,
    action: str,
    *,
    owner_roles: set[str] = {"treasurer"},
) -> None:
    assert_owner_or_admin(expense.recorded_by, current_user, action, owner_roles=owner_roles)
    assert_record_scope(current_user, expense)


def _read_receipt_image(file: UploadFile):
    allowed_types = {"image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic"}
    if file.content_type not in allowed_types:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Unsupported file type '{file.content_type}'. "
                f"Allowed: {', '.join(sorted(allowed_types))}"
            ),
        )

    raw_bytes = file.file.read(10 * 1024 * 1024 + 1)

    max_size_bytes = 10 * 1024 * 1024
    if not raw_bytes or len(raw_bytes) > max_size_bytes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Receipt image must be between 1 byte and 10MB",
        )

    try:
        processed_bytes, content_type = prepare_image_for_upload(raw_bytes)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Could not process the uploaded image",
        )

    return raw_bytes, processed_bytes, content_type


@router.post("/scan-receipt", response_model=ScanReceiptResponse, status_code=status.HTTP_200_OK)
def scan_receipt(
    file: UploadFile = File(...),
    organization_id: uuid.UUID | None = Form(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_financial_access),
):
    selected_id = organization_id or current_user.organization_id
    organization = db.query(Organization).filter(Organization.id == selected_id).first()
    if organization is None:
        raise HTTPException(400, "Select an existing organization for this receipt")
    resolve_organization_id(db, current_user, selected_id, organization.department_id)
    if current_user.role != "super_admin" and current_user.department_id != organization.department_id:
        raise HTTPException(403, "Receipt organization must belong to your assigned department")
    _, processed_bytes, content_type = _read_receipt_image(file)

    try:
        receipt_url = upload_receipt_image(processed_bytes, content_type, current_user.id, organization.id)
    except RuntimeError:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Receipt service is unavailable")
    except StorageError:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Receipt storage upload failed")

    try:
        parsed = parse_receipt_image(processed_bytes, content_type)
    except RuntimeError:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Receipt service is unavailable")
    except ReceiptParseError:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Receipt parsing failed")
    except Exception:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Receipt parsing service is unavailable")

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

    if payload.receipt and payload.receipt_url:
        try:
            urls = [canonical_file_url(str(url), settings.supabase_receipts_bucket)
                    for url in (payload.receipt.receipt_url, payload.receipt_url)]
        except ValueError:
            raise HTTPException(422, "Receipt URL must identify a valid receipt object")
        if urls[0] != urls[1]:
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
    db.flush()

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
    current_user: User = Depends(require_financial_access),
):
    expense = _get_expense_or_404(db, expense_id, lock=True)
    _assert_expense_owner_scope(expense, current_user, "edit")

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
        if updates["receipt_url"] is None and recorded_receipt:
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
    expense = _get_expense_or_404(db, expense_id, lock=True)
    assert_record_scope(current_user, expense)
    assert_not_self_review(expense.recorded_by, current_user)

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Expense is '{expense.status}' — only pending expenses can be approved",
        )

    assert_receipt_review_complete(db, expense)
    if db.query(ExpenseItem).filter(ExpenseItem.expense_id == expense.id, ExpenseItem.category == "asset").first():
        if not db.query(Receipt).filter(Receipt.expense_id == expense.id).first():
            raise HTTPException(409, "Record the asset purchase receipt before submitting expense approval")

    category = db.query(Category).filter(Category.id == expense.category_id).with_for_update().first()
    if category is None:
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

    record_decision(db, "expense", expense.id, "approved", current_user, payload.remarks)
    expense.status = "approved"
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
    expense = _get_expense_or_404(db, expense_id, lock=True)
    assert_record_scope(current_user, expense)
    assert_not_self_review(expense.recorded_by, current_user)

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Expense is '{expense.status}' — only pending expenses can be rejected",
        )

    record_decision(db, "expense", expense.id, "rejected", current_user, payload.remarks)
    expense.status = "rejected"
    db.commit()
    db.refresh(expense)
    return expense


@router.post("/{expense_id}/receipt", response_model=ExpenseOut)
def upload_receipt(
    expense_id: uuid.UUID,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_financial_access),
):
    expense = _get_expense_or_404(db, expense_id, lock=True)
    _assert_expense_owner_scope(expense, current_user, "attach a receipt to")

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only pending expenses can have a receipt attached",
        )

    existing_receipt = receipt_for_transaction(db, expense)
    if existing_receipt and existing_receipt.review_status in {"cleared", "rejected"}:
        raise HTTPException(409, "Reviewed receipt evidence is immutable")
    raw_bytes, processed_bytes, content_type = _read_receipt_image(file)
    digest = hashlib.sha256(raw_bytes).hexdigest()
    db.query(Organization).filter(Organization.id == expense.organization_id).with_for_update().first()
    duplicates = db.query(Receipt).filter(Receipt.organization_id == expense.organization_id,
        Receipt.file_sha256 == digest)
    if existing_receipt:
        duplicates = duplicates.filter(Receipt.id != existing_receipt.id)
    if duplicates.first():
        raise HTTPException(409, "This receipt file has already been recorded")

    try:
        receipt_url = upload_receipt_image(processed_bytes, content_type, current_user.id, expense.organization_id)
    except RuntimeError:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Receipt service is unavailable")
    except StorageError:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Receipt storage upload failed")

    expense.receipt_url = receipt_url
    sync_expense_receipt(db, expense, current_user, file_sha256=digest)
    db.commit()
    db.refresh(expense)
    return expense


@router.post("/{expense_id}/parse-receipt", response_model=ExpenseOut)
def parse_receipt(
    expense_id: uuid.UUID,
    payload: ReceiptParseRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_financial_access),
):
    expense = _get_expense_or_404(db, expense_id, lock=True)
    _assert_expense_owner_scope(expense, current_user, "attach a receipt scan to")

    if expense.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only pending expenses can have a receipt scan attached",
        )

    try:
        parsed = parse_receipt_text(payload.raw_text)
    except RuntimeError:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Receipt service is unavailable")
    except ReceiptParseError:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Receipt parsing failed")
    except Exception:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Receipt parsing service is unavailable")

    expense.ocr_merchant = parsed["merchant"]
    expense.ocr_date = parsed["date"]
    expense.ocr_amount = parsed["amount"]
    if expense.receipt_url:
        sync_expense_receipt(db, expense, current_user)

    if parsed["amount"] is not None:
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
    current_user: User = Depends(require_financial_access),
):
    expense = _get_expense_or_404(db, expense_id, lock=True)
    _assert_expense_owner_scope(expense, current_user, "delete")

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
    expense = _get_expense_or_404(db, expense_id, lock=True)
    return complete_purchase(db, expense, payload, current_user)
