"""Administrative changes are recorded in the same transaction as the change."""

from app.models import AuditLog


def record_access_change(db, actor, action, target, details=None):
    db.add(AuditLog(
        user_id=actor.id,
        action=action,
        entity_type=target.__tablename__,
        entity_id=target.id,
        organization_id=getattr(target, "organization_id", None),
        department_id=getattr(target, "department_id", None),
        details=details,
    ))
