"""Approved expenses enter stock only after documented payment and delivery."""
from datetime import datetime, timezone
from decimal import Decimal
from fastapi import HTTPException
from sqlalchemy import func
from app.dependencies import assert_owner_or_admin, assert_record_scope
from app.models import Event, ExpenseItem, Inventory, InventoryTransaction, Organization, Receipt
from app.services.access_audit import record_access_change
from app.services.receipt_validation import assert_receipt_review_complete


def complete_purchase(db, expense, payload, user):
    assert_record_scope(user, expense)
    assert_owner_or_admin(expense.recorded_by, user, "complete purchases", owner_roles={"treasurer"})
    if expense.status != "approved":
        raise HTTPException(409, "An expense must be approved before purchase completion")
    if expense.purchase_completed_at is not None:
        raise HTTPException(409, "This purchase is already completed; stock will not be added twice")
    if payload.paid_amount != Decimal(str(expense.amount)):
        raise HTTPException(422, "Full recorded payment must match the expense amount")
    event = db.query(Event).filter(Event.id == expense.event_id).first()
    if event is None:
        raise HTTPException(409, "Assign the expense to its event before completing a purchase")
    assert_record_scope(user, event)
    if event.organization_id != expense.organization_id or event.department_id != expense.department_id:
        raise HTTPException(409, "Purchase and event ownership do not match")
    receipt = db.query(Receipt).filter(Receipt.expense_id == expense.id).first()
    if receipt is None or not receipt.purpose.strip():
        raise HTTPException(409, "Record a purpose-bearing receipt linked to this expense first")
    if receipt.event_id != event.id or Decimal(str(receipt.amount)) != payload.paid_amount:
        raise HTTPException(409, "Receipt event and amount must match the completed purchase")
    assert_receipt_review_complete(db, expense)
    all_items = db.query(ExpenseItem).filter(ExpenseItem.expense_id == expense.id).order_by(ExpenseItem.name, ExpenseItem.id).all()
    items = [row for row in all_items if row.category == "asset"]
    if not items:
        raise HTTPException(409, "This expense has no asset items to receive into inventory")
    if sum((Decimal(str(row.amount)) for row in all_items), Decimal("0.00")) > payload.paid_amount:
        raise HTTPException(409, "Itemized line amounts exceed the recorded purchase total")
    confirmations = {row.expense_item_id: row for row in payload.items}
    if len(confirmations) != len(payload.items) or set(confirmations) != {row.id for row in items}:
        raise HTTPException(422, "Confirm each asset expense item exactly once, without foreign items")
    if any(row.converted_inventory_id is not None for row in items):
        raise HTTPException(409, "Legacy asset items were already converted; reconcile them instead of adding stock again")
    db.query(Organization).filter(Organization.id == expense.organization_id).with_for_update().first()
    # Validate every target before changing any balances or stock.
    targets = {}
    for row in items:
        confirmation = confirmations[row.id]
        key = row.name.strip().casefold()
        if not key:
            raise HTTPException(409, "Asset item names must be recorded")
        item = targets.get(key)
        if item is None:
            item = db.query(Inventory).filter(func.lower(Inventory.item_name) == row.name.strip().lower(),
                Inventory.organization_id == expense.organization_id).with_for_update().first()
        if item:
            if item.department_id != expense.department_id or item.event_id is None:
                raise HTTPException(409, "Repair the existing catalog item's ownership and event link first")
            if item.unit.strip().casefold() != confirmation.unit.casefold():
                raise HTTPException(422, "Confirmed unit must match the existing catalog unit")
        else:
            item = Inventory(item_name=row.name.strip(), organization_id=expense.organization_id,
                department_id=expense.department_id, event_id=event.id, quantity=0,
                description=f"Received from completed purchase {expense.id}",
                unit=confirmation.unit, low_stock_threshold=5, is_draft=True)
        targets[key] = item
    expense.paid_on = payload.paid_on
    expense.received_on = payload.received_on
    expense.paid_amount = payload.paid_amount
    expense.payment_method = payload.payment_method
    expense.payment_reference = payload.payment_reference
    expense.purchase_vendor = payload.vendor
    expense.purchase_completed_at = datetime.now(timezone.utc)
    db.add_all(list(targets.values()))
    db.flush()
    movements = []
    for row in items:
        confirmation = confirmations[row.id]
        item = targets[row.name.strip().casefold()]
        row.quantity = confirmation.quantity
        row.unit = confirmation.unit
        row.converted_inventory_id = item.id
        item.quantity += confirmation.quantity
        movements.append(InventoryTransaction(inventory_id=item.id, event_id=event.id,
            expense_item_id=row.id, transaction_type="purchase", change_qty=confirmation.quantity,
            reason=f"Completed purchase {expense.id}", performed_by=user.id))
    db.flush()
    db.add_all(movements)
    record_access_change(db, user, "purchase.completed", expense,
        {"payment_reference": payload.payment_reference, "asset_items": len(items)})
    db.commit()
    db.refresh(expense)
    return expense
