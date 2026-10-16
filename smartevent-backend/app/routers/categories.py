import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import (
    assert_record_scope,
    require_operational_read,
    require_role,
    resolve_department_id,
    resolve_organization_id,
    scope_query_by_department,
)
from app.models import Category, Event, Expense, User
from app.schemas import CategoryCreate, CategoryOut, CategoryUpdate

router = APIRouter(prefix="/categories", tags=["categories"])


@router.post("", response_model=CategoryOut, status_code=status.HTTP_201_CREATED)
def create_category(
    payload: CategoryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    department_id = resolve_department_id(
        current_user,
        payload.department_id,
        require_for_admin=True,
    )
    organization_id = resolve_organization_id(db, current_user, payload.organization_id, department_id)
    existing = db.query(Category).filter(
        func.lower(Category.name) == payload.name.lower(),
        Category.organization_id == organization_id,
    ).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A category with this name already exists",
        )

    category = Category(
        department_id=department_id,
        organization_id=organization_id,
        name=payload.name,
        allocated_budget=payload.allocated_budget,
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
    current_user: User = Depends(require_operational_read),
):
    query = scope_query_by_department(db.query(Category), Category.department_id, current_user)
    return query.order_by(Category.name).all()


@router.get("/{category_id}", response_model=CategoryOut)
def get_category(
    category_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    category = db.query(Category).filter(Category.id == category_id).first()
    if category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")
    assert_record_scope(current_user, category, allow_officer_read=True)
    return category


@router.patch("/{category_id}", response_model=CategoryOut)
def update_category(
    category_id: uuid.UUID,
    payload: CategoryUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    category = db.query(Category).filter(Category.id == category_id).with_for_update().first()
    if category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")

    assert_record_scope(current_user, category)

    updates = payload.model_dump(exclude_unset=True)
    if "allocated_budget" in updates:
        remaining = Decimal(str(category.remaining_budget)) + Decimal(str(updates["allocated_budget"])) - Decimal(str(category.allocated_budget))
        if remaining < 0:
            raise HTTPException(409, "Allocated budget cannot be less than the amount already spent")
        updates["remaining_budget"] = remaining

    if "department_id" in updates:
        if updates["department_id"] != category.department_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only admins can change a category's department scope",
            )
        updates["department_id"] = resolve_department_id(
            current_user,
            updates["department_id"],
            require_for_admin=True,
        )

    if "name" in updates and updates["name"] != category.name:
        name_taken = (
            db.query(Category)
            .filter(func.lower(Category.name) == updates["name"].lower(), Category.id != category_id,
                    Category.organization_id == category.organization_id)
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
    category = db.query(Category).filter(Category.id == category_id).with_for_update().first()
    if category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")

    assert_record_scope(current_user, category)

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
