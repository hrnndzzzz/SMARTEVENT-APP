"""Dry-run legacy receipt import. Use --apply --actor-email SUPER_ADMIN_EMAIL to persist."""
import argparse
from fastapi import HTTPException
from pydantic import ValidationError
from app.database import SessionLocal
from app.models import Expense, Receipt, User
from app.schemas import ReceiptDetails
from app.services.receipt_validation import save_receipt
from app.services.access_audit import record_access_change


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Persist imports (default is rollback-only)")
    parser.add_argument("--actor-email", required=True, help="Active Super Admin for scope checks/audit")
    args = parser.parse_args()
    with SessionLocal() as db:
        actor = db.query(User).filter(User.email == args.actor_email, User.role == "super_admin",
            User.is_active.is_(True), User.is_suspended.is_(False), User.must_change_password.is_(False)).first()
        if actor is None:
            parser.error("An active, fully provisioned Super Admin is required")
        actor_id = actor.id
        ids = [row.id for row in db.query(Expense).outerjoin(Receipt, Receipt.expense_id == Expense.id)
               .filter(Expense.receipt_url.is_not(None), Receipt.id.is_(None)).order_by(Expense.created_at).all()]
        imported = blocked = 0
        for expense_id in ids:
            try:
                transaction = db.query(Expense).filter(Expense.id == expense_id).with_for_update().one()
                actor = db.get(User, actor_id)
                details = ReceiptDetails(receipt_url=transaction.receipt_url, purpose=transaction.description,
                    merchant=transaction.ocr_merchant, issued_on=transaction.ocr_date or transaction.expense_date,
                    amount=transaction.amount)
                receipt = save_receipt(db, transaction, details, actor, allow_historical=True)
                receipt.recorded_by = transaction.recorded_by
                record_access_change(db, actor, "receipt.legacy_imported", receipt, {"expense_id": str(transaction.id)})
                if args.apply:
                    db.commit()
                else:
                    db.rollback()
                imported += 1
                print(f"{expense_id}: {'imported' if args.apply else 'eligible (dry run)'}")
            except (HTTPException, ValidationError) as exc:
                db.rollback()
                blocked += 1
                # Print only record IDs and safe validation messages, never receipt URLs.
                reason = exc.detail if isinstance(exc, HTTPException) else "Invalid historical receipt metadata"
                print(f"{expense_id}: needs review: {reason}")
        print(f"{'Applied' if args.apply else 'Dry run'}: {imported} eligible/imported, {blocked} blocked")


if __name__ == "__main__":
    main()
