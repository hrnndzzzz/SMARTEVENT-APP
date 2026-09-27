"""Personal notification inbox, independent of operational edit permissions."""
import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from app.database import get_db
from app.dependencies import require_active_account
from app.models import Notification, User
from app.schemas import NotificationOut

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=list[NotificationOut])
def list_notifications(unread_only: bool = False, limit: int = Query(50, ge=1, le=100),
                       offset: int = Query(0, ge=0), db: Session = Depends(get_db),
                       current_user: User = Depends(require_active_account)):
    query = db.query(Notification).filter(Notification.user_id == current_user.id)
    if unread_only:
        query = query.filter(Notification.read_at.is_(None))
    return query.order_by(Notification.created_at.desc(), Notification.id).offset(offset).limit(limit).all()


@router.get("/unread-count")
def unread_count(db: Session = Depends(get_db), current_user: User = Depends(require_active_account)):
    return {"unread_count": db.query(Notification).filter(
        Notification.user_id == current_user.id, Notification.read_at.is_(None)).count()}


@router.patch("/{notification_id}/read", response_model=NotificationOut)
def mark_read(notification_id: uuid.UUID, db: Session = Depends(get_db),
              current_user: User = Depends(require_active_account)):
    notification = db.query(Notification).filter(
        Notification.id == notification_id, Notification.user_id == current_user.id).first()
    if notification is None:
        raise HTTPException(404, "Notification not found")
    if notification.read_at is None:
        notification.read_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(notification)
    return notification
