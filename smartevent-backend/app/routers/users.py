"""Administrative user listing and Admin department assignment."""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import assert_record_scope, require_role, resolve_organization_id
from app.models import CiteMember, Department, Organization, User
from app.schemas import UserAccessUpdate, UserDepartmentUpdate, UserOut
from app.services.access_audit import record_access_change

router = APIRouter(prefix="/users", tags=["users"])


@router.get(
    "",
    response_model=list[UserOut],
    summary="List users in the authorized department scope",
)
def list_users(
    department_id: uuid.UUID | None = Query(default=None),
    is_active: bool | None = Query(default=None),
    organization_id: uuid.UUID | None = Query(default=None),
    is_suspended: bool | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    query = db.query(User)
    if current_user.role == "super_admin":
        if department_id is not None:
            query = query.filter(User.department_id == department_id)
        if organization_id is not None:
            query = query.filter(User.organization_id == organization_id)
    else:
        assert_record_scope(current_user, current_user)
        if organization_id is not None and organization_id != current_user.organization_id:
            raise HTTPException(status_code=403, detail="You can only list your assigned organization")
        if department_id is not None and department_id != current_user.department_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only list users in your assigned department.",
            )
        query = query.filter(
            User.department_id == current_user.department_id,
            User.organization_id == current_user.organization_id,
            User.role.in_(["adviser", "treasurer", "officer"]),
        )

    if is_active is not None:
        query = query.filter(User.is_active.is_(is_active))
    if is_suspended is not None:
        query = query.filter(User.is_suspended.is_(is_suspended))
    return query.order_by(User.full_name).all()


@router.patch(
    "/{user_id}/department",
    response_model=UserOut,
    summary="Assign an existing Admin to a department",
    description="Super_Admin only. Use this to scope existing Admin accounts that were created before department assignment was required.",
)
def assign_admin_department(
    user_id: uuid.UUID,
    payload: UserDepartmentUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("super_admin")),
):
    target_user = db.query(User).filter(User.id == user_id).first()
    if target_user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    if target_user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only Admin accounts can be reassigned through this endpoint.",
        )

    department = db.query(Department).filter(Department.id == payload.department_id).first()
    if department is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="department_id does not match any existing department",
        )

    organization_id = resolve_organization_id(db, current_user, payload.organization_id, department.id)
    before = {"department_id": str(target_user.department_id), "organization_id": str(target_user.organization_id)}
    target_user.department_id = department.id
    target_user.organization_id = organization_id
    record_access_change(db, current_user, "user.scope_changed", target_user, before)
    db.commit()
    db.refresh(target_user)
    return target_user


@router.patch("/{user_id}/access", response_model=UserOut)
def update_user_access(
    user_id: uuid.UUID,
    payload: UserAccessUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    target = db.query(User).filter(User.id == user_id).with_for_update().first()
    if target is None:
        raise HTTPException(status_code=404, detail="User not found")
    if target.id == current_user.id or target.role == "super_admin":
        raise HTTPException(status_code=403, detail="Your own access and Super Admin access cannot be changed here")
    updates = payload.model_dump(exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=422, detail="Provide at least one access change")
    if any(value is None for key, value in updates.items() if key != "position"):
        raise HTTPException(status_code=422, detail="Access fields cannot be null")
    member_roles = {"adviser", "treasurer", "officer"}
    if current_user.role != "super_admin":
        assert_record_scope(current_user, target)
        if target.role not in member_roles or updates.get("role", target.role) not in member_roles:
            raise HTTPException(status_code=403, detail="Admins can manage only adviser, treasurer, and officer accounts")
        if "organization_id" in updates:
            raise HTTPException(status_code=403, detail="Only Super Admin can transfer an account")
    new_role = updates.get("role", target.role)
    if new_role == "sds_staff":
        if "organization_id" in updates:
            raise HTTPException(status_code=422, detail="SDS staff does not belong to an organization")
        updates["department_id"] = None
        updates["organization_id"] = None
    else:
        organization_id = updates.get("organization_id", target.organization_id)
        organization = db.query(Organization).filter(Organization.id == organization_id).first()
        if organization is None:
            raise HTTPException(status_code=400, detail="Assign a valid organization")
        updates["department_id"] = organization.department_id
        updates["organization_id"] = organization.id
    before = {
        "role": target.role, "is_suspended": target.is_suspended,
        "organization_id": str(target.organization_id), "department_id": str(target.department_id),
    }
    for field, value in updates.items():
        setattr(target, field, value)
    # Keep the claimed roster consistent; public registration never chooses a role.
    member = db.query(CiteMember).filter(CiteMember.claimed_by_user_id == target.id).first()
    if member is not None:
        if new_role not in member_roles:
            raise HTTPException(status_code=409, detail="Roster accounts must retain an adviser, treasurer, or officer role")
        member.role = target.role
        member.position = target.position
        member.department_id = target.department_id
        member.organization_id = target.organization_id
    record_access_change(db, current_user, "user.access_changed", target, {
        "before": before,
        "after": {key: str(getattr(target, key)) for key in before},
    })
    db.commit()
    db.refresh(target)
    return target
