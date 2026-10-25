"""
Event Proposal Letters — formal documents submitted per event, kept as
a separate entity from the Event record itself (title/description/
status/budget). This module exists specifically to give the sds_staff
role something real to do: SDS's only permission in this system is
READING these letters — they have no access to events, expenses,
categories, or inventory otherwise.
"""

import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import (
    assert_record_scope,
    require_event_proposer,
    require_role,
    scope_query_by_department,
)
from app.models import Event, EventProposalLetter, User
from app.schemas import EventProposalLetterOut
from app.services.storage import StorageError, upload_proposal_letter

router = APIRouter(prefix="/proposal-letters", tags=["proposal-letters"])

# PDF is the expected real-world format for a formal letter; JPEG/PNG
# covers a phone photo of a printed/signed letter as a fallback.
_ALLOWED_TYPES = {
    "application/pdf": "pdf",
    "image/jpeg": "jpg",
    "image/png": "png",
}


def _require_letter_reader(user: User = Depends(require_role("sds_staff", "treasurer", "adviser", "admin", "officer"))) -> User:
    if user.role == "officer":
        require_event_proposer(user)
    return user


def _assert_letter_scope(user: User, event: Event) -> None:
    assert_record_scope(user, event, allow_officer_read=True)
    if user.role == "officer" and event.proposed_by != user.id:
        raise HTTPException(status_code=403, detail="You can only access letters for your own proposals")


@router.post("", response_model=EventProposalLetterOut, status_code=status.HTTP_201_CREATED)
async def upload_proposal_letter_route(
    event_id: uuid.UUID = Form(...),
    title: str = Form(..., min_length=1, max_length=200),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_event_proposer),
):
    event = db.query(Event).filter(Event.id == event_id).first()
    if event is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    _assert_letter_scope(current_user, event)
    if current_user.role == "officer" and event.status not in {"draft", "rejected"}:
        raise HTTPException(status_code=409, detail="Letters can only be uploaded to draft or rejected proposals")

    if file.content_type not in _ALLOWED_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Unsupported file type '{file.content_type}'. "
                f"Allowed: PDF, JPEG, PNG"
            ),
        )

    raw_bytes = await file.read()
    max_size_bytes = 10 * 1024 * 1024
    if len(raw_bytes) > max_size_bytes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File too large. Maximum size is 10MB",
        )

    extension = _ALLOWED_TYPES[file.content_type]
    try:
        document_url = upload_proposal_letter(raw_bytes, file.content_type, extension)
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))
    except StorageError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc))

    letter = EventProposalLetter(
        event_id=event_id,
        title=title,
        document_url=document_url,
        submitted_by=current_user.id,
    )
    db.add(letter)
    db.commit()
    db.refresh(letter)
    return letter


@router.get("", response_model=list[EventProposalLetterOut])
def list_proposal_letters(
    db: Session = Depends(get_db),
    current_user: User = Depends(_require_letter_reader),
):
    query = db.query(EventProposalLetter).join(Event, Event.id == EventProposalLetter.event_id)
    if current_user.role not in {"sds_staff", "super_admin"}:
        query = scope_query_by_department(
            query, Event.department_id, current_user, allow_officer_read=True
        )
    if current_user.role == "officer":
        query = query.filter(Event.proposed_by == current_user.id)
    return query.order_by(EventProposalLetter.created_at.desc()).all()


@router.get("/{letter_id}", response_model=EventProposalLetterOut)
def get_proposal_letter(
    letter_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(_require_letter_reader),
):
    letter = db.query(EventProposalLetter).filter(EventProposalLetter.id == letter_id).first()
    if letter is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Proposal letter not found")
    if current_user.role not in {"sds_staff", "super_admin"}:
        event = db.query(Event).filter(Event.id == letter.event_id).first()
        if event is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
        _assert_letter_scope(current_user, event)
    return letter
