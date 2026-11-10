"""Durable registration confirmation; failed email delivery never revokes approval."""
import base64
from datetime import datetime, timezone
import logging
import uuid

from app.models import Notification, Organization
from app.services.email import send_email

logger = logging.getLogger(__name__)


def check_registration_assignment(db, member, user=None):
    from fastapi import HTTPException
    from app.rbac_policy import ROSTER_ROLES, SCHOOL_REVIEWER_ROLES
    if member.role in SCHOOL_REVIEWER_ROLES:
        valid = member.department_id is None and member.organization_id is None
    else:
        organization = db.query(Organization).filter(Organization.id == member.organization_id).first()
        # Blank department only where the organization has none; an Admin always needs one.
        valid = (member.role in ROSTER_ROLES and organization is not None
                 and organization.department_id == member.department_id
                 and (member.department_id is not None or member.role != "admin"))
    if not valid:
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


def _sap_form_attachment(db, notification, user):
    """The SDS Office's copy of the filled form, on the email telling it a proposal has arrived."""
    payload = notification.payload or {}
    if notification.kind != "sap_workflow" or payload.get("action") != "sap_dean_approved" or user.role != "sds_staff":
        return None
    from app.models_sap import SAPRevision
    revision = db.query(SAPRevision).filter_by(proposal_id=uuid.UUID(payload["proposal_id"]),
                                               revision_no=payload["revision_no"]).first()
    if revision is None:
        return None
    return [{"filename": f"SAP-revision-{revision.revision_no}.pdf",
             "content": base64.b64encode(revision.printable_pdf).decode()}]


def deliver_notification(db, notification_id):
    notification = db.query(Notification).filter(Notification.id == notification_id).with_for_update().first()
    if notification is None or notification.email_status == "sent":
        return
    from app.models import User
    user = db.query(User).filter(User.id == notification.user_id).first()
    notification.email_attempts += 1
    try:
        send_email(user.email, notification.title, notification.body,
                   idempotency_key=f"{'registration-confirmation' if notification.kind == 'registration_confirmation' else notification.kind}/{notification.id}",
                   attachments=_sap_form_attachment(db, notification, user))
        notification.email_status = "sent"
        notification.email_sent_at = datetime.now(timezone.utc)
    except Exception:
        notification.email_status = "failed"
        logger.warning("Email delivery failed for notification %s", notification.id)
    db.commit()
