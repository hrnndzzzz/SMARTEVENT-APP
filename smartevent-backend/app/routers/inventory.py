"""
CRUD for physical inventory items (chairs, extension cords, tarpaulins,
markers, etc.) plus a transaction log for every change in stock.

Design note — no DB trigger for quantity (unlike categories):
    categories.remaining_budget is only ever touched by the
    fn_deduct_category_balance trigger. There's no equivalent trigger
    on inventory_transactions in the current schema, so this router
    updates Inventory.quantity itself, in the same commit as the
    InventoryTransaction row that explains the change. If a DB trigger
    for this gets added later, remove the manual quantity update below
    to avoid double-counting.

Access rules:
  - Anyone logged in can VIEW items and their low-stock status.
  - Only admins can CREATE, UPDATE (metadata), or DELETE items —
    same reasoning as categories: these define the org's actual
    physical inventory, not something any officer should redefine.
  - Any logged-in user can record a transaction (check items out for
    an event, log a return, note damage/loss) — that's normal day-to-day
    org activity, not an admin-only action.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, require_role
from app.models import Inventory, InventoryTransaction, User
from app.schemas import (
    InventoryCreate,
    InventoryOut,
    InventoryTransactionCreate,
    InventoryTransactionOut,
    InventoryUpdate,
)

router = APIRouter(prefix="/inventory", tags=["inventory"])


def _get_item_or_404(db: Session, inventory_id: uuid.UUID) -> Inventory:
    item = db.query(Inventory).filter(Inventory.id == inventory_id).first()
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Inventory item not found")
    return item


@router.post("", response_model=InventoryOut, status_code=status.HTTP_201_CREATED)
def create_item(
    payload: InventoryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    existing = db.query(Inventory).filter(Inventory.item_name == payload.item_name).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="An item with this name already exists",
        )

    item = Inventory(
        item_name=payload.item_name,
        description=payload.description,
        quantity=payload.quantity,
        unit=payload.unit,
        low_stock_threshold=payload.low_stock_threshold,
        location=payload.location,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.get("", response_model=list[InventoryOut])
def list_items(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return db.query(Inventory).order_by(Inventory.item_name).all()


# NOTE: this route must be declared before GET /{inventory_id}, or
# FastAPI will try to parse "low-stock" as a UUID and 422 instead.
@router.get("/low-stock", response_model=list[InventoryOut])
def list_low_stock_items(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return (
        db.query(Inventory)
        .filter(Inventory.quantity <= Inventory.low_stock_threshold)
        .order_by(Inventory.quantity)
        .all()
    )


@router.get("/{inventory_id}", response_model=InventoryOut)
def get_item(
    inventory_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return _get_item_or_404(db, inventory_id)


@router.get("/{inventory_id}/transactions", response_model=list[InventoryTransactionOut])
def list_item_transactions(
    inventory_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    _get_item_or_404(db, inventory_id)
    return (
        db.query(InventoryTransaction)
        .filter(InventoryTransaction.inventory_id == inventory_id)
        .order_by(InventoryTransaction.created_at.desc())
        .all()
    )


@router.patch("/{inventory_id}", response_model=InventoryOut)
def update_item(
    inventory_id: uuid.UUID,
    payload: InventoryUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    item = _get_item_or_404(db, inventory_id)

    updates = payload.model_dump(exclude_unset=True)

    if "item_name" in updates and updates["item_name"] != item.item_name:
        name_taken = (
            db.query(Inventory)
            .filter(Inventory.item_name == updates["item_name"], Inventory.id != inventory_id)
            .first()
        )
        if name_taken:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="An item with this name already exists",
            )

    for field, value in updates.items():
        setattr(item, field, value)

    db.commit()
    db.refresh(item)
    return item


@router.delete("/{inventory_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_item(
    inventory_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    item = _get_item_or_404(db, inventory_id)

    in_use = (
        db.query(InventoryTransaction)
        .filter(InventoryTransaction.inventory_id == inventory_id)
        .first()
    )
    if in_use:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "This item has recorded transactions and cannot be deleted. "
                "Consider setting quantity to 0 instead to retire it."
            ),
        )

    db.delete(item)
    db.commit()
    return None


@router.post(
    "/{inventory_id}/transactions",
    response_model=InventoryTransactionOut,
    status_code=status.HTTP_201_CREATED,
)
def create_transaction(
    inventory_id: uuid.UUID,
    payload: InventoryTransactionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = _get_item_or_404(db, inventory_id)

    new_quantity = item.quantity + payload.change_qty
    if new_quantity < 0:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"Not enough stock: only {item.quantity} {item.unit} of "
                f"'{item.item_name}' available, but this would remove "
                f"{-payload.change_qty}"
            ),
        )

    transaction = InventoryTransaction(
        inventory_id=item.id,
        event_id=payload.event_id,
        change_qty=payload.change_qty,
        reason=payload.reason,
        performed_by=current_user.id,
    )
    db.add(transaction)

    item.quantity = new_quantity  # manual update — see module docstring

    db.commit()
    db.refresh(transaction)
    return transaction
