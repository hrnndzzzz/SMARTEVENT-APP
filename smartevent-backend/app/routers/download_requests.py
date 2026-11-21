"""Requests for the app from the public website.

The website at smartevent-website.vercel.app describes the system and
offers the Android build, but not to anybody who happens to find the
page: whoever wants it says who they are and why, and the department
decides. This is the half of that the server owns.

Two audiences, so two routers. The form POSTs from a browser with no
account and no token, so `public_router` carries that one route and
nothing else, rate-limited in the middleware the way the sign-in routes
are. Reading the requests and deciding them is ordinary admin work and
sits behind the usual role check.

What the visitor is told back is deliberately thin — a status and a
sentence. The row itself, with the reason they gave and whatever the
department wrote about it, is not for the public internet.
"""

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.dependencies import ADMIN_ROLES, require_role
from app.models import DownloadRequest, Notification, User
from app.schemas import (
    DownloadRequestAck, DownloadRequestCreate, DownloadRequestDecision, DownloadRequestOut,
)
from app.services.access_audit import record_access_change
from app.services.email import EmailError, send_download_link_email

public_router = APIRouter(prefix="/download-requests", tags=["download requests"])
router = APIRouter(prefix="/download-requests", tags=["download requests"])


def _notify_admins(db: Session, request: DownloadRequest) -> None:
    """Puts the request in front of whoever can act on it.

    In the app's own inbox rather than an email: the department already
    carries SMARTEVENT, the notification list is already there, and a
    mailer that is not configured would lose the request silently.
    Every active administrator is told, the way the SDS Office is told
    about a proposal — one of them deals with it, and the rest see it
    has been dealt with when the list says so.
    """
    recipients = db.query(User.id).filter(
        User.role.in_(ADMIN_ROLES), User.is_active.is_(True), User.is_suspended.is_(False),
    ).all()
    for (recipient,) in recipients:
        db.add(Notification(
            user_id=recipient,
            kind='download_request',
            title='App download requested',
            body=f'{request.name} ({request.organization}) asked for the app.',
            payload={'download_request_id': str(request.id), 'email': request.email},
            # The notice lives in the app; there is no email behind it.
            email_status='sent',
        ))


@public_router.post("", response_model=DownloadRequestAck, status_code=201)
def create_download_request(payload: DownloadRequestCreate, db: Session = Depends(get_db)):
    """Takes a request from the website. No account, no token.

    The duplicate check is the database's, not a read followed by a
    write: two submissions arriving at once would both find nothing and
    both insert. The partial unique index on a pending address is what
    makes the website's 409 true.
    """
    request = DownloadRequest(**payload.model_dump())
    db.add(request)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        # The one constraint a visitor can trip. Said plainly, because
        # this sentence reaches a member of the public.
        raise HTTPException(409, "There is already a request from this address waiting") from None
    _notify_admins(db, request)
    db.commit()
    return DownloadRequestAck(
        status="pending",
        message=(
            "Request received. If the department approves it, the download link goes "
            "to this address."
        ),
    )


@router.get("", response_model=list[DownloadRequestOut])
def list_download_requests(
    status: str | None = Query(None, pattern="^(pending|approved|rejected)$"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role(*ADMIN_ROLES)),
):
    """The requests, newest first. Pending ones are the ones that need somebody."""
    query = db.query(DownloadRequest)
    if status:
        query = query.filter(DownloadRequest.status == status)
    return (query.order_by(DownloadRequest.created_at.desc(), DownloadRequest.id)
            .offset(offset).limit(limit).all())


@router.get("/pending-count")
def pending_count(db: Session = Depends(get_db),
                  current_user: User = Depends(require_role(*ADMIN_ROLES))):
    """Just the number, for a badge, without pulling the list."""
    return {"pending_count": db.query(func.count(DownloadRequest.id)).filter(
        DownloadRequest.status == 'pending').scalar() or 0}


@router.post("/{request_id}/decide", response_model=DownloadRequestOut)
def decide_download_request(
    request_id: uuid.UUID,
    payload: DownloadRequestDecision,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role(*ADMIN_ROLES)),
):
    """Approves or refuses one request, once.

    The email is attempted after the decision is recorded and cannot
    undo it. A server with no mailer configured, or a Resend outage,
    would otherwise make a decision impossible to record at all — and
    the department can always send the link by hand. `email_status`
    says whether that is still owed.
    """
    request = db.get(DownloadRequest, request_id)
    if request is None:
        raise HTTPException(404, "Download request not found")
    if request.status != 'pending':
        raise HTTPException(409, f"This request was already {request.status}")

    request.status = 'approved' if payload.approve else 'rejected'
    request.decided_by = current_user.id
    request.decided_at = datetime.now(timezone.utc)
    request.note = payload.note

    if payload.approve and settings.app_download_url:
        try:
            send_download_link_email(request.email, request.name, settings.app_download_url)
            request.email_status = 'sent'
        except (EmailError, RuntimeError):
            # Including an unconfigured mailer, which raises RuntimeError.
            # The approval stands; the row records that the link still
            # has to reach them.
            request.email_status = 'failed'

    record_access_change(db, current_user, f'download_request_{request.status}', request,
                         details={'email': request.email, 'email_status': request.email_status})
    db.commit()
    db.refresh(request)
    return request
