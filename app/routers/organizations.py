"""Organization ownership and administrator lookup."""

import uuid
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.dependencies import assert_record_scope, require_role
from app.models import Department, Organization, User
from app.schemas import OrganizationCreate, OrganizationOut
from app.services.access_audit import record_access_change

router = APIRouter(prefix="/organizations", tags=["organizations"])


@router.get("", response_model=list[OrganizationOut])
def list_organizations(db: Session = Depends(get_db), current_user: User = Depends(require_role("admin"))):
    query = db.query(Organization)
    if current_user.role != "super_admin":
        assert_record_scope(current_user, current_user)
        query = query.filter(Organization.id == current_user.organization_id)
    return query.order_by(Organization.name).all()


@router.post("", response_model=OrganizationOut, status_code=status.HTTP_201_CREATED)
def create_organization(payload: OrganizationCreate, db: Session = Depends(get_db), current_user: User = Depends(require_role("super_admin"))):
    if db.query(Department).filter(Department.id == payload.department_id).first() is None:
        raise HTTPException(status_code=400, detail="Department does not exist")
    code = payload.code.strip().upper()
    name = payload.name.strip()
    if not code or not name:
        raise HTTPException(status_code=422, detail="Organization code and name cannot be blank")
    if db.query(Organization).filter(Organization.code == code).first() is not None:
        raise HTTPException(status_code=409, detail="Organization code already exists")
    organization = Organization(code=code, name=name, department_id=payload.department_id)
    db.add(organization)
    db.flush()
    record_access_change(db, current_user, "organization.created", organization)
    db.commit()
    db.refresh(organization)
    return organization
