import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import (
    require_event_proposer,
    require_proposal_letter_reader,
)
from app.models import Event, EventProposalLetter, User
from app.schemas import EventProposalLetterOut
from app.services.storage import MAX_UPLOAD_BYTES, StorageError, prepare_image_for_upload, upload_proposal_letter
from app.services.event_routing import assert_event_read, scope_event_query

router = APIRouter(prefix="/proposal-letters", tags=["proposal-letters"])

_ALLOWED_TYPES = {
    "application/pdf": "pdf",
    "image/jpeg": "jpg",
    "image/png": "png",
}


def _assert_letter_scope(db: Session, user: User, event: Event) -> None:
    assert_event_read(db, event, user)
    if user.role == "officer" and event.proposed_by != user.id:
        raise HTTPException(status_code=403, detail="You can only access letters for your own proposals")


@router.post("", response_model=EventProposalLetterOut, status_code=status.HTTP_201_CREATED)
def upload_proposal_letter_route(
    event_id: uuid.UUID = Form(...),
    title: str = Form(..., min_length=1, max_length=200),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_event_proposer),
):
    event = db.query(Event).filter(Event.id == event_id).first()
    if event is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    _assert_letter_scope(db, current_user, event)
    if current_user.role == "officer" and event.status not in {"draft", "rejected"}:
        raise HTTPException(status_code=409, detail="Letters can only be uploaded to draft or rejected proposals")
    if event.organization_id is None:
        raise HTTPException(409, "Assign the event to an organization before uploading documents")

    if file.content_type not in _ALLOWED_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Unsupported file type '{file.content_type}'. "
                f"Allowed: PDF, JPEG, PNG"
            ),
        )

    raw_bytes = file.file.read(MAX_UPLOAD_BYTES + 1)
    if not raw_bytes or len(raw_bytes) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File must be between 1 byte and 10MB",
        )

    extension = _ALLOWED_TYPES[file.content_type]
    content_type = file.content_type
    if content_type == "application/pdf":
        if not raw_bytes.startswith(b"%PDF-") or b"%%EOF" not in raw_bytes[-1024:]:
            raise HTTPException(400, "Upload a valid PDF document")
    else:
        try:
            raw_bytes, content_type = prepare_image_for_upload(raw_bytes)
            extension = "jpg"
        except Exception:
            raise HTTPException(400, "Could not process the proposal letter image") from None
    try:
        document_url = upload_proposal_letter(raw_bytes, content_type, extension, current_user.id, event.organization_id)
    except RuntimeError:
        raise HTTPException(503, "Proposal letter storage is not configured") from None
    except StorageError:
        raise HTTPException(502, "Proposal letter storage upload failed") from None

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
    current_user: User = Depends(require_proposal_letter_reader),
):
    query = db.query(EventProposalLetter).join(Event, Event.id == EventProposalLetter.event_id)
    if current_user.role not in {"sds_staff", "super_admin"}:
        query = scope_event_query(query, db, current_user)
    if current_user.role == "officer":
        query = query.filter(Event.proposed_by == current_user.id)
    return query.order_by(EventProposalLetter.created_at.desc()).all()


@router.get("/{letter_id}", response_model=EventProposalLetterOut)
def get_proposal_letter(
    letter_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_proposal_letter_reader),
):
    letter = db.query(EventProposalLetter).filter(EventProposalLetter.id == letter_id).first()
    if letter is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Proposal letter not found")
    if current_user.role not in {"sds_staff", "super_admin"}:
        event = db.query(Event).filter(Event.id == letter.event_id).first()
        if event is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
        _assert_letter_scope(db, current_user, event)
    return letter
