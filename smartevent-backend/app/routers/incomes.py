"""Record and list received event income by source and purpose."""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.dependencies import (
    assert_record_scope,
    require_financial_access,
    require_operational_read,
    resolve_department_id,
    resolve_organization_id,
    scope_query_by_department,
)
from app.models import Event, IncomeRecord, User
from app.schemas import IncomeCreate, IncomeOut
from app.services.academic_year import validate_school_year
from app.services.receipt_validation import save_receipt
from app.services.access_audit import record_access_change

router = APIRouter(prefix="/incomes", tags=["incomes"])


@router.post("", response_model=IncomeOut, status_code=status.HTTP_201_CREATED)
def record_income(
    payload: IncomeCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_financial_access),
):
    fields = dict(source=payload.source, source_type=payload.source_type, purpose=payload.purpose,
                  amount=payload.amount, received_on=payload.received_on, recorded_by=current_user.id)
    if payload.event_id is None:
        # General fund: owned by the recorder's own organization.
        try:
            validate_school_year(payload.school_year)
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        department_id = resolve_department_id(current_user, None)
        organization_id = resolve_organization_id(db, current_user, None, department_id)
        income = IncomeRecord(event_id=None, organization_id=organization_id, department_id=department_id,
                              school_year=payload.school_year, semester=payload.semester, **fields)
        audited = income
    else:
        event = db.query(Event).filter(Event.id == payload.event_id).first()
        if event is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="event_id does not match any existing event",
            )
        assert_record_scope(current_user, event, allow_officer_read=True)
        income = IncomeRecord(event_id=event.id, **fields)
        audited = event
    db.add(income)
    db.flush()
    if payload.receipt:
        save_receipt(db, income, payload.receipt, current_user)
    record_access_change(db, current_user, "income.recorded", audited, {"income_id": str(income.id), "source": income.source, "amount": str(income.amount)})
    db.commit()
    db.refresh(income)
    return income


@router.get("", response_model=list[IncomeOut])
def list_income(
    event_id: uuid.UUID | None = Query(default=None),
    # Off by default: app builds before general-fund income read every
    # row's event_id as present.
    include_general: bool = Query(default=False),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    query = db.query(IncomeRecord).options(selectinload(IncomeRecord.receipt)).join(Event, Event.id == IncomeRecord.event_id)
    query = scope_query_by_department(query, Event.department_id, current_user)
    if event_id is not None:
        query = query.filter(IncomeRecord.event_id == event_id)
    rows = query.all()
    if include_general and event_id is None:
        rows += scope_query_by_department(
            db.query(IncomeRecord).options(selectinload(IncomeRecord.receipt))
            .filter(IncomeRecord.event_id.is_(None)),
            IncomeRecord.department_id, current_user,
        ).all()
    return sorted(rows, key=lambda row: (row.received_on, row.created_at), reverse=True)
