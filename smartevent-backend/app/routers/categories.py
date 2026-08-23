"""
CRUD for budget categories (e.g. "Supplies", "Venue", "Food") — the
department-wide budget pool that expenses draw down against.

Access rules:
  - Anyone logged in can VIEW categories (officers need to see budgets
    to know what they can spend, advisers need to see them to approve).
  - Only admins can CREATE, UPDATE, or DELETE categories, since these
    define the department's actual budget structure.

Note on remaining_budget: it is never set directly through this router.
It only changes via the database trigger (fn_deduct_category_balance)
that fires when an expense's status flips to 'approved'. That's why
CategoryUpdate in schemas.py has no remaining_budget field — there's
nothing here for a client to send that would bypass the trigger.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, require_role
from app.models import Category, User
from app.schemas import CategoryCreate, CategoryOut, CategoryUpdate

router = APIRouter(prefix="/categories", tags=["categories"])


@router.post("", response_model=CategoryOut, status_code=status.HTTP_201_CREATED)
def create_category(
    payload: CategoryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    existing = db.query(Category).filter(Category.name == payload.name).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A category with this name already exists",
        )

    category = Category(
        name=payload.name,
        allocated_budget=payload.allocated_budget,
        # A brand-new category starts with its full allocation available —
        # remaining_budget only ever decreases from here via the trigger.
        remaining_budget=payload.allocated_budget,
        low_balance_threshold=payload.low_balance_threshold,
        created_by=current_user.id,
    )
    db.add(category)
    db.commit()
    db.refresh(category)
    return category


@router.get("", response_model=list[CategoryOut])
def list_categories(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return db.query(Category).order_by(Category.name).all()


@router.get("/{category_id}", response_model=CategoryOut)
def get_category(
    category_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")
    return category


@router.patch("/{category_id}", response_model=CategoryOut)
def update_category(
    category_id: uuid.UUID,
    payload: CategoryUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")

    updates = payload.model_dump(exclude_unset=True)

    if "name" in updates and updates["name"] != category.name:
        name_taken = (
            db.query(Category)
            .filter(Category.name == updates["name"], Category.id != category_id)
            .first()
        )
        if name_taken:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A category with this name already exists",
            )

    for field, value in updates.items():
        setattr(category, field, value)

    db.commit()
    db.refresh(category)
    return category


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_category(
    category_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")

    # Categories are referenced by events and expenses (category_id FK).
    # Deleting one that's already in use would either fail on the FK
    # constraint or, worse, orphan those records depending on your DB
    # settings. Block deletion if anything still references it, and
    # point the admin toward the safer alternative.
    from app.models import Event, Expense  # local import avoids a circular import at module load

    in_use = (
        db.query(Event).filter(Event.category_id == category_id).first()
        or db.query(Expense).filter(Expense.category_id == category_id).first()
    )
    if in_use:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "This category is referenced by existing events or expenses "
                "and cannot be deleted. Consider setting allocated_budget to 0 "
                "instead to retire it."
            ),
        )

    db.delete(category)
    db.commit()
    return None
