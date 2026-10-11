"""
Department-admin-managed roster of pre-approved officers, advisers,
and treasurers. Super_Admin can manage the roster across departments;
POST /auth/register validates against it and auto-assigns the role.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import assert_record_scope, assert_department_scope, require_role, resolve_department_id, resolve_organization_id
from app.models import CiteMember, Organization, User
from app.schemas import CiteMemberCreate, CiteMemberOut, CiteMemberUpdate
from app.services.access_audit import record_access_change

router = APIRouter(prefix="/cite-members", tags=["cite-members"])


@router.post("", response_model=CiteMemberOut, status_code=status.HTTP_201_CREATED)
def add_cite_member(
    payload: CiteMemberCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    """Add an approved roster member; the member completes account setup through OTP registration."""
    department_id = resolve_department_id(
        current_user,
        payload.department_id,
        require_for_admin=True,
    )
    organization_id = resolve_organization_id(db, current_user, payload.organization_id, department_id)
    existing = db.query(CiteMember).filter(CiteMember.email == payload.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This email is already on the CITE roster",
        )

    member = CiteMember(
        full_name=payload.full_name,
        email=payload.email,
        role=payload.role,
        position=payload.position,
        department_id=department_id,
        organization_id=organization_id,
    )
    db.add(member)
    db.flush()
    record_access_change(db, current_user, "roster.created", member)
    db.commit()
    db.refresh(member)
    return member


@router.get("", response_model=list[CiteMemberOut])
def list_cite_members(
    department_id: uuid.UUID | None = Query(
        default=None,
        description="Optional department filter. Admins are restricted to their assigned department; only Super_Admin can select another department.",
    ),
    claimed: bool | None = Query(
        default=None,
        description="Filter by whether the roster entry has completed registration.",
    ),
    organization_id: uuid.UUID | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    """List approved roster members in the caller's authorized department scope."""
    query = db.query(CiteMember)
    if current_user.role == "super_admin":
        if department_id is not None:
            query = query.filter(CiteMember.department_id == department_id)
        if organization_id is not None:
            query = query.filter(CiteMember.organization_id == organization_id)
    else:
        assert_record_scope(current_user, current_user)
        if organization_id is not None and organization_id != current_user.organization_id:
            raise HTTPException(status_code=403, detail="You can only list your assigned organization")
        if department_id is not None and department_id != current_user.department_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only list members in your assigned department.",
            )
        query = query.filter(CiteMember.department_id == current_user.department_id, CiteMember.organization_id == current_user.organization_id)

    if claimed is not None:
        query = query.filter(
            CiteMember.claimed_by_user_id.is_not(None)
            if claimed
            else CiteMember.claimed_by_user_id.is_(None)
        )
    return query.order_by(CiteMember.full_name).all()


@router.patch("/{member_id}", response_model=CiteMemberOut)
def update_cite_member(
    member_id: uuid.UUID, payload: CiteMemberUpdate,
    db: Session = Depends(get_db), current_user: User = Depends(require_role("admin")),
):
    member = db.query(CiteMember).filter(CiteMember.id == member_id).with_for_update().first()
    if member is None:
        raise HTTPException(status_code=404, detail="Roster entry not found")
    assert_record_scope(current_user, member)
    if member.claimed_by_user_id is not None:
        raise HTTPException(status_code=409, detail="Manage this registered account through /users/{user_id}/access")
    updates = payload.model_dump(exclude_unset=True)
    if not updates or any(value is None for key, value in updates.items() if key != "position"):
        raise HTTPException(status_code=422, detail="Provide non-null role or organization fields, or a position")
    if "organization_id" in updates:
        if current_user.role != "super_admin":
            raise HTTPException(status_code=403, detail="Only Super Admin can transfer roster entries")
        organization = db.query(Organization).filter(Organization.id == updates["organization_id"]).first()
        if organization is None:
            raise HTTPException(status_code=400, detail="Organization does not exist")
        updates["department_id"] = organization.department_id
    before = {"role": member.role, "position": member.position, "organization_id": str(member.organization_id)}
    for field, value in updates.items():
        setattr(member, field, value)
    record_access_change(db, current_user, "roster.updated", member, {"before": before})
    db.commit()
    db.refresh(member)
    return member


@router.delete("/{member_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_cite_member(
    member_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    member = db.query(CiteMember).filter(CiteMember.id == member_id).first()
    if member is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="CITE member not found")

    assert_record_scope(current_user, member)

    if member.claimed_by_user_id is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "This roster entry has already been claimed by an account "
                "and cannot be removed. Suspend the user through "
                "PATCH /users/{user_id}/access if access needs to be revoked."
            ),
        )

    record_access_change(db, current_user, "roster.removed", member)
    db.delete(member)
    db.commit()
    return None
