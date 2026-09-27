"""Read-only administrative audit history."""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from app.database import get_db
from app.dependencies import require_role, scope_query_by_department
from app.models import AuditLog, User
from app.schemas import AuditLogOut

router = APIRouter(prefix="/audit-logs", tags=["audit-logs"])


@router.get("", response_model=list[AuditLogOut])
def list_audit_logs(
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    query = scope_query_by_department(db.query(AuditLog), AuditLog.department_id, current_user)
    return query.order_by(AuditLog.created_at.desc(), AuditLog.id).offset(offset).limit(limit).all()
