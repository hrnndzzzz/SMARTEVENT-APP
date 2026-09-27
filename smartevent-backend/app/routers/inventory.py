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
    - Super Admin can view all items. Admins and other scoped roles see
        only items in their own department.
  - Only admins can CREATE, UPDATE (metadata), or DELETE items —
    same reasoning as categories: these define the org's actual
    physical inventory, not something any officer should redefine.
  - Adviser/Treasurer transactions are limited to items in their own
    department.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import (
    assert_department_scope,
    assert_record_scope,
    require_operational_read,
    require_role,
    resolve_department_id,
    resolve_organization_id,
    scope_query_by_department,
)
from app.models import Event, ExpenseItem, Inventory, InventoryTransaction, Organization, User
from app.services.access_audit import record_access_change
from app.schemas import (
    InventoryCreate,
    InventoryOut,
    InventoryTransactionCreate,
    InventoryTransactionOut,
    InventoryTransactionRepair,
    InventoryUpdate,
)

router = APIRouter(prefix="/inventory", tags=["inventory"])


def _event_for_item(db, event_id, user, organization_id, department_id):
    event = db.query(Event).filter(Event.id == event_id).first()
    if event is None:
        raise HTTPException(400, "Event does not exist")
    assert_record_scope(user, event)
    if event.organization_id != organization_id or event.department_id != department_id:
        raise HTTPException(400, "Inventory and event must share an organization and department")
    return event


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
    department_id = resolve_department_id(
        current_user,
        payload.department_id,
        require_for_admin=True,
    )
    organization_id = resolve_organization_id(db, current_user, payload.organization_id, department_id)
    _event_for_item(db, payload.event_id, current_user, organization_id, department_id)
    db.query(Organization).filter(Organization.id == organization_id).with_for_update().first()
    existing = db.query(Inventory).filter(
        func.lower(Inventory.item_name) == payload.item_name.lower(),
        Inventory.organization_id == organization_id,
    ).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="An item with this name already exists",
        )

    item = Inventory(
        department_id=department_id,
        organization_id=organization_id,
        event_id=payload.event_id,
        item_name=payload.item_name,
        description=payload.description,
        quantity=payload.quantity,
        unit=payload.unit,
        low_stock_threshold=payload.low_stock_threshold,
        location=payload.location,
    )
    db.add(item)
    db.flush()
    if payload.quantity > 0:
        db.add(InventoryTransaction(inventory_id=item.id, event_id=payload.event_id,
            transaction_type=payload.initial_transaction_type, change_qty=payload.quantity,
            reason=payload.reason, performed_by=current_user.id))
    record_access_change(db, current_user, "inventory.created", item)
    db.commit()
    db.refresh(item)
    return item


@router.get("", response_model=list[InventoryOut])
def list_items(
    is_draft: bool | None = None,
    event_id: uuid.UUID | None = None,
    missing_event: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    """
    is_draft=true is the review queue for catalog items created by
    documented purchase completion from asset expense lines.
    Omit the param entirely to see everything, draft or not.
    """
    query = scope_query_by_department(
        db.query(Inventory), Inventory.department_id, current_user
    )
    if is_draft is not None:
        query = query.filter(Inventory.is_draft == is_draft)
    if event_id is not None:
        linked = db.query(InventoryTransaction.inventory_id).filter(InventoryTransaction.event_id == event_id)
        query = query.filter(or_(Inventory.event_id == event_id, Inventory.id.in_(linked)))
    if missing_event:
        query = query.filter(Inventory.event_id.is_(None))
    return query.order_by(Inventory.item_name).all()


# NOTE: this route must be declared before GET /{inventory_id}, or
# FastAPI will try to parse "low-stock" as a UUID and 422 instead.
@router.get("/low-stock", response_model=list[InventoryOut])
def list_low_stock_items(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    query = scope_query_by_department(
        db.query(Inventory), Inventory.department_id, current_user
    )
    return (
        query
        .filter(Inventory.quantity <= Inventory.low_stock_threshold)
        .order_by(Inventory.quantity)
        .all()
    )


@router.get("/{inventory_id}", response_model=InventoryOut)
def get_item(
    inventory_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    item = _get_item_or_404(db, inventory_id)
    assert_record_scope(current_user, item, allow_officer_read=True)
    return item


@router.post("/{inventory_id}/confirm-draft", response_model=InventoryOut)
def confirm_draft_item(
    inventory_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    """
    Admin review step for items auto-created by approve_expense from a
    scanned 'asset' receipt line. Flips is_draft to False — everything
    else about the item (name, quantity, etc.) is left as-is; if it
    needs correcting, use PATCH /{inventory_id} either before or after
    confirming, they're independent actions.
    """
    item = _get_item_or_404(db, inventory_id)
    assert_record_scope(current_user, item)

    if not item.is_draft:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This item is not a draft — nothing to confirm",
        )

    if item.event_id is None:
        raise HTTPException(409, "Assign this legacy item to its intended event first")
    item.is_draft = False
    record_access_change(db, current_user, "inventory.draft_confirmed", item)
    db.commit()
    db.refresh(item)
    return item


@router.get("/{inventory_id}/transactions", response_model=list[InventoryTransactionOut])
def list_item_transactions(
    inventory_id: uuid.UUID,
    event_id: uuid.UUID | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    item = _get_item_or_404(db, inventory_id)
    assert_record_scope(current_user, item, allow_officer_read=True)
    query = db.query(InventoryTransaction).filter(InventoryTransaction.inventory_id == inventory_id)
    if event_id:
        query = query.filter(InventoryTransaction.event_id == event_id)
    return query.order_by(InventoryTransaction.created_at.desc()).all()


@router.patch("/{inventory_id}/transactions/{transaction_id}/metadata", response_model=InventoryTransactionOut)
def repair_transaction_metadata(inventory_id: uuid.UUID, transaction_id: uuid.UUID,
                                 payload: InventoryTransactionRepair, db: Session = Depends(get_db),
                                 current_user: User = Depends(require_role("admin"))):
    item = _get_item_or_404(db, inventory_id)
    assert_record_scope(current_user, item)
    _event_for_item(db, payload.event_id, current_user, item.organization_id, item.department_id)
    row = db.query(InventoryTransaction).filter(InventoryTransaction.id == transaction_id,
        InventoryTransaction.inventory_id == inventory_id).with_for_update().first()
    if row is None:
        raise HTTPException(404, "Inventory transaction not found")
    if row.transaction_type != "legacy" and row.event_id is not None:
        raise HTTPException(409, "Only incomplete legacy movement metadata can be repaired")
    if row.expense_item_id is not None:
        raise HTTPException(409, "Purchase provenance cannot be changed by legacy repair")
    if row.event_id is not None and row.event_id != payload.event_id:
        raise HTTPException(409, "Repair cannot replace an already recorded event")
    qty = row.change_qty
    if payload.transaction_type in {"opening_balance", "acquisition", "donation", "return"} and qty <= 0:
        raise HTTPException(422, "Incoming types require positive historic quantity")
    if payload.transaction_type in {"issue", "disposal"} and qty >= 0:
        raise HTTPException(422, "Outgoing types require negative historic quantity")
    row.event_id = payload.event_id
    row.transaction_type = payload.transaction_type
    row.reason = payload.reason
    record_access_change(db, current_user, "inventory.legacy_movement_repaired", item,
        {"transaction_id": str(row.id), "event_id": str(row.event_id), "transaction_type": row.transaction_type})
    db.commit()
    db.refresh(row)
    return row


@router.patch("/{inventory_id}", response_model=InventoryOut)
def update_item(
    inventory_id: uuid.UUID,
    payload: InventoryUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    item = _get_item_or_404(db, inventory_id)
    assert_record_scope(current_user, item)

    updates = payload.model_dump(exclude_unset=True)
    if "unit" in updates and updates["unit"].casefold() != item.unit.casefold():
        if item.quantity != 0 or db.query(InventoryTransaction).filter(InventoryTransaction.inventory_id == item.id).first():
            raise HTTPException(409, "Units cannot be changed while stock or movement history exists")
    if "event_id" in updates:
        _event_for_item(db, updates["event_id"], current_user, item.organization_id, item.department_id)
        if item.event_id is not None and updates["event_id"] != item.event_id:
            raise HTTPException(409, "The initial event link is immutable; use event-linked movements for subsequent usage")
    if item.event_id is None and "event_id" not in updates:
        raise HTTPException(409, "Assign a legacy item's event before editing it")

    if "item_name" in updates and updates["item_name"] != item.item_name:
        db.query(Organization).filter(Organization.id == item.organization_id).with_for_update().first()
        name_taken = (
            db.query(Inventory)
            .filter(func.lower(Inventory.item_name) == updates["item_name"].lower(), Inventory.id != inventory_id,
                    Inventory.organization_id == item.organization_id)
            .first()
        )
        if name_taken:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="An item with this name already exists",
            )

    for field, value in updates.items():
        setattr(item, field, value)
    record_access_change(db, current_user, "inventory.updated", item, {"fields": list(updates)})

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
    assert_record_scope(current_user, item)

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
                "Use an event-linked disposal transaction to retire stock."
            ),
        )

    if db.query(ExpenseItem).filter(ExpenseItem.converted_inventory_id == item.id).first():
        raise HTTPException(409, "Purchased inventory evidence cannot be deleted")
    if item.quantity != 0:
        raise HTTPException(409, "Only zero-stock items without history can be deleted")
    record_access_change(db, current_user, "inventory.deleted", item)
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
    current_user: User = Depends(require_role("treasurer", "adviser", "admin")),
):
    item = db.query(Inventory).filter(Inventory.id == inventory_id).with_for_update().first()
    if item is None:
        raise HTTPException(404, "Inventory item not found")
    assert_record_scope(current_user, item)
    if item.event_id is None:
        raise HTTPException(409, "Assign the legacy inventory item's intended event first")
    if item.is_draft:
        raise HTTPException(409, "An administrator must confirm this catalog draft before stock movements")
    if payload.transaction_type == "purchase":
        raise HTTPException(409, "Purchased stock must use POST /expenses/{expense_id}/complete-purchase")

    if payload.event_id is not None:
        event = db.query(Event).filter(Event.id == payload.event_id).first()
        if event is None:
            raise HTTPException(status_code=400, detail="Event does not exist")
        assert_record_scope(current_user, event)
        if event.organization_id != item.organization_id or event.department_id != item.department_id:
            raise HTTPException(status_code=400, detail="Inventory and event must share an organization")

    new_quantity = item.quantity + payload.change_qty
    if payload.transaction_type == "return":
        net_issued = db.query(func.coalesce(func.sum(InventoryTransaction.change_qty), 0)).filter(
            InventoryTransaction.inventory_id == item.id, InventoryTransaction.event_id == payload.event_id,
            InventoryTransaction.transaction_type.in_(["issue", "return"])).scalar()
        if payload.change_qty > -net_issued:
            raise HTTPException(409, "Return quantity exceeds outstanding issues for this event")
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
        transaction_type=payload.transaction_type,
        change_qty=payload.change_qty,
        reason=payload.reason,
        performed_by=current_user.id,
    )
    db.add(transaction)

    item.quantity = new_quantity  # manual update — see module docstring
    record_access_change(db, current_user, "inventory.movement_recorded", item,
        {"event_id": str(payload.event_id), "transaction_type": payload.transaction_type, "change_qty": payload.change_qty})

    db.commit()
    db.refresh(transaction)
    return transaction
