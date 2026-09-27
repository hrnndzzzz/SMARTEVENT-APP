"""Record and list received event income by source and purpose."""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.dependencies import (
    assert_department_scope,
    assert_record_scope,
    require_financial_access,
    require_operational_read,
    scope_query_by_department,
)
from app.models import Event, IncomeRecord, User
from app.schemas import IncomeCreate, IncomeOut
from app.services.receipt_validation import save_receipt
from app.services.access_audit import record_access_change

router = APIRouter(prefix="/incomes", tags=["incomes"])


@router.post("", response_model=IncomeOut, status_code=status.HTTP_201_CREATED)
def record_income(
    payload: IncomeCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_financial_access),
):
    event = db.query(Event).filter(Event.id == payload.event_id).first()
    if event is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="event_id does not match any existing event",
        )
    assert_record_scope(current_user, event)

    income = IncomeRecord(
        event_id=event.id,
        source=payload.source,
        source_type=payload.source_type,
        purpose=payload.purpose,
        amount=payload.amount,
        received_on=payload.received_on,
        recorded_by=current_user.id,
    )
    db.add(income)
    db.flush()
    if payload.receipt:
        save_receipt(db, income, payload.receipt, current_user)
    record_access_change(db, current_user, "income.recorded", event, {"income_id": str(income.id), "source": income.source, "amount": str(income.amount)})
    db.commit()
    db.refresh(income)
    return income


@router.get("", response_model=list[IncomeOut])
def list_income(
    event_id: uuid.UUID | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    query = db.query(IncomeRecord).options(selectinload(IncomeRecord.receipt)).join(Event, Event.id == IncomeRecord.event_id)
    query = scope_query_by_department(query, Event.department_id, current_user)
    if event_id is not None:
        query = query.filter(IncomeRecord.event_id == event_id)
    return query.order_by(IncomeRecord.received_on.desc(), IncomeRecord.created_at.desc()).all()
