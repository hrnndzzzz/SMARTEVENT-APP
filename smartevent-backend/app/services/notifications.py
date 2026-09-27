"""Durable registration confirmation; failed email delivery never revokes approval."""
from datetime import datetime, timezone
import logging

from app.models import Notification, Organization
from app.services.email import send_email

logger = logging.getLogger(__name__)


def check_registration_assignment(db, member, user=None):
    from fastapi import HTTPException
    organization = db.query(Organization).filter(Organization.id == member.organization_id).first()
    if (member.role not in {"officer", "adviser", "treasurer"}
            or member.department_id is None or organization is None
            or organization.department_id != member.department_id):
        raise HTTPException(403, "An administrator must provide a valid roster role and organization assignment")
    if user is not None and (member.claimed_by_user_id != user.id
            or user.role != member.role or user.department_id != member.department_id
            or user.organization_id != member.organization_id):
        raise HTTPException(403, "Registration eligibility has changed. Contact an administrator.")


def queue_registration_confirmation(db, user):
    notification = Notification(
        user_id=user.id, kind="registration_confirmation",
        title="Registration approved",
        body=f"Hi {user.full_name}, your SMARTEVENT registration has been verified and automatically approved. You can now log in.",
        email_status="pending",
    )
    db.add(notification)
    return notification


def deliver_notification(db, notification_id):
    # A row lock serializes immediate delivery and scheduled retries.
    notification = db.query(Notification).filter(Notification.id == notification_id).with_for_update().first()
    if notification is None or notification.email_status == "sent":
        return
    from app.models import User
    user = db.query(User).filter(User.id == notification.user_id).first()
    notification.email_attempts += 1
    try:
        send_email(user.email, notification.title, notification.body,
                   idempotency_key=f"registration-confirmation/{notification.id}")
        notification.email_status = "sent"
        notification.email_sent_at = datetime.now(timezone.utc)
    except Exception:
        # Provider failures are retryable; no secrets/provider errors are exposed to clients.
        notification.email_status = "failed"
        logger.warning("Registration confirmation email delivery failed for notification %s", notification.id)
    db.commit()
