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

from fastapi import APIRouter, Depends, HTTPException, status
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
)

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
