"""Read-only administrative audit history."""

import uuid
from typing import Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_
from sqlalchemy.orm import Session
from app.database import get_db
from app.dependencies import require_operational_read, require_role, scope_query_by_department
from app.models import AuditLog, Category, Event, Expense, Inventory, Receipt, User
from app.schemas import ActivityNoteOut, AuditLogOut

router = APIRouter(prefix="/audit-logs", tags=["audit-logs"])

# Only these actions reach ordinary members; roster and account history stays admin-only.
ACTIVITY_AREAS = {
    "proposals": ("sap_", "event."),
    "inventory": ("inventory.",),
    "finance": ("income.", "expense.", "receipt.", "purchase.", "category."),
}
SUBJECTS = {
    "inventory": (Inventory, "item_name"),
    "events": (Event, "title"),
    "expenses": (Expense, "description"),
    "receipts": (Receipt, "merchant"),
    "categories": (Category, "name"),
}


@router.get("", response_model=list[AuditLogOut])
def list_audit_logs(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin", "adviser")),
):
    query = scope_query_by_department(db.query(AuditLog), AuditLog.department_id, current_user)
    return query.order_by(AuditLog.created_at.desc(), AuditLog.id).offset(offset).limit(limit).all()


@router.get("/latest", response_model=ActivityNoteOut | None)
def latest_activity(
    area: Literal["proposals", "inventory", "finance"],
    entity_id: uuid.UUID | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    """Who last changed something in an area, or in one record of it, for every member to see."""
    query = db.query(AuditLog, User.full_name).join(User, User.id == AuditLog.user_id)
    query = scope_query_by_department(query, AuditLog.department_id, current_user)
    query = query.filter(or_(*(AuditLog.action.startswith(p, autoescape=True) for p in ACTIVITY_AREAS[area])))
    if entity_id is not None:
        query = query.filter(AuditLog.entity_id == entity_id)
    row = query.order_by(AuditLog.created_at.desc(), AuditLog.id.desc()).first()
    if row is None:
        return None
    log, actor_name = row
    details = log.details if isinstance(log.details, dict) else {}
    subject = details.get("name") or details.get("source")
    if subject is None and log.entity_type in SUBJECTS:
        model, field = SUBJECTS[log.entity_type]
        subject = db.query(getattr(model, field)).filter(model.id == log.entity_id).scalar()
    return ActivityNoteOut(action=log.action, actor_name=actor_name, created_at=log.created_at, subject=subject)
