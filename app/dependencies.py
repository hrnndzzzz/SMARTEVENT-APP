"""Shared authentication and authorization dependencies.

The six values in :data:`VALID_ROLES` are the only application roles. The
helpers in this module keep routers from re-implementing authorization with
slightly different rules.

Department scope is fail-closed. A scoped route must pass the department id
of the record it loaded to :func:`assert_department_scope`; ``None`` is not
treated as a match. This prevents records with missing ownership data from
becoming accidentally visible to non-admin users.
"""

import uuid

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Organization, User
from app.security import decode_access_token


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")


VALID_ROLES = {
    "super_admin",
    "admin",
    "adviser",
    "treasurer",
    "officer",
    "sds_staff",
}
ADMIN_ROLES = {"admin", "super_admin"}
SCOPED_OPERATIONAL_ROLES = {"adviser", "treasurer"}
SCOPED_READ_ROLES = SCOPED_OPERATIONAL_ROLES | {"officer"}
FINANCIAL_ROLES = ADMIN_ROLES | {"treasurer"}
APPROVER_ROLES = ADMIN_ROLES | {"adviser"}


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    """Decode the bearer token and load an active user."""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    user_id = decode_access_token(token)
    if user_id is None:
        raise credentials_exception

    try:
        user = db.query(User).filter(User.id == uuid.UUID(user_id)).first()
    except ValueError:
        raise credentials_exception

    if user is None or not user.is_active or user.is_suspended:
        raise credentials_exception

    if user.role not in VALID_ROLES:
        raise credentials_exception

    return user


def require_active_account(user: User = Depends(get_current_user)) -> User:
    """Reject temporary-password accounts outside password change flow."""
    if user.must_change_password:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Password change required before accessing this resource",
        )
    return user


def ensure_account_ready_for_app(user: User) -> User:
    """Guard against temporary-password accounts even when a caller bypasses the auth dependency override."""
    if getattr(user, "is_suspended", False):
        raise HTTPException(status_code=403, detail="This account is suspended")
    if getattr(user, "must_change_password", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Password change required before accessing this resource",
        )
    return user


def require_role(*allowed_roles: str):
    """Build a role dependency; ``admin`` always includes ``super_admin``."""
    unknown_roles = set(allowed_roles) - VALID_ROLES
    if unknown_roles:
        raise ValueError(f"Unknown application role(s): {', '.join(sorted(unknown_roles))}")

    effective_roles = set(allowed_roles)
    if "admin" in effective_roles:
        effective_roles.add("super_admin")

    def role_checker(user: User = Depends(require_active_account)) -> User:
        user = ensure_account_ready_for_app(user)
        ensure_operational_assignment(user)
        if user.role not in effective_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Requires one of these roles: {', '.join(sorted(effective_roles))}",
            )
        return user

    return role_checker


def enforce_read_only(
    request: Request,
    user: User = Depends(require_active_account),
) -> User:
    """Allow officers only safe HTTP methods when this dependency is used."""
    user = ensure_account_ready_for_app(user)
    if user.role == "officer" and request.method not in ("GET", "HEAD", "OPTIONS"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Role '{user.role}' has read-only access. {request.method} requests are forbidden.",
        )
    return user


def require_financial_access(
    user: User = Depends(require_active_account),
) -> User:
    """Permit financial execution only for Treasurer/Admin/Super Admin."""
    user = ensure_account_ready_for_app(user)
    ensure_operational_assignment(user)
    if user.role not in FINANCIAL_ROLES:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Financial access restricted to treasurer, admin, or super_admin",
        )
    return user


def require_operational_read(
    user: User = Depends(require_active_account),
) -> User:
    """Allow operational reads, excluding SDS staff."""
    user = ensure_account_ready_for_app(user)
    ensure_operational_assignment(user)
    if user.role not in ADMIN_ROLES | SCOPED_READ_ROLES:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This role has no access to operational data",
        )
    return user


def assert_department_scope(
    user: User,
    record_department_id: uuid.UUID | None,
    *,
    allow_officer_read: bool = False,
) -> None:
    """Check access to a loaded record's department scope.

    Super Admin is global. Admin, Adviser, and Treasurer can access their
    own department. Officer can access their own department only when the
    caller explicitly enables read-only scope. SDS staff never receives
    operational access. Missing scope data is denied for every non-Super-Admin.
    """
    if user.role == "super_admin":
        return

    allowed_roles = (SCOPED_READ_ROLES | {"admin"}) if allow_officer_read else (SCOPED_OPERATIONAL_ROLES | {"admin"})
    if user.role not in allowed_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Role '{user.role}' is not permitted to access this scoped record",
        )

    if user.department_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account has no department assigned. Contact an administrator.",
        )

    if record_department_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This record has no department scope and cannot be accessed by your role.",
        )

    if user.department_id != record_department_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only access records belonging to your own department.",
        )


def enforce_department_scope(
    record_department_id: uuid.UUID | None,
    *,
    allow_officer_read: bool = False,
):
    """FastAPI dependency wrapper for routes with a pre-resolved scope."""
    def checker(user: User = Depends(require_active_account)) -> None:
        assert_department_scope(
            user,
            record_department_id,
            allow_officer_read=allow_officer_read,
        )

    return checker


def assert_owner_or_admin(
    owner_id: uuid.UUID,
    current_user: User,
    action: str,
    *,
    owner_roles: set[str] = SCOPED_OPERATIONAL_ROLES,
) -> None:
    """Enforce owner-only work for scoped operational roles."""
    if current_user.role in ADMIN_ROLES:
        return
    if current_user.role not in owner_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Role '{current_user.role}' cannot {action} this record",
        )
    if owner_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"You can only {action} records you own",
        )


def assert_not_self_review(submitter_id: uuid.UUID, current_user: User) -> None:
    """Prevent the submitter of an event/expense from approving or rejecting it."""
    if submitter_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You cannot approve or reject a record that you submitted.",
        )


def scope_query_by_department(
    query,
    department_column,
    current_user: User,
    *,
    allow_officer_read: bool = True,
):
    """Restrict a query using explicit department and organization FKs.

    Super Admins retain global visibility. Admins and other operational
    readers must have both assignments, and the query is narrowed to
    that organization within its department. This helper is for models such as ``Event`` and
    ``Expense`` that carry their own ``department_id`` rather than only an
    owner FK.
    """
    current_user = ensure_account_ready_for_app(current_user)
    if current_user.role == "super_admin":
        return query

    allowed_roles = (SCOPED_READ_ROLES | {"admin"}) if allow_officer_read else (SCOPED_OPERATIONAL_ROLES | {"admin"})
    if current_user.role not in allowed_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Role '{current_user.role}' is not permitted to access scoped data",
        )
    if current_user.department_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account has no department assigned. Contact an administrator.",
        )

    organization_id = getattr(current_user, "organization_id", None)
    if organization_id is None:
        raise HTTPException(status_code=403, detail="Your account has no organization assigned")
    model = department_column.class_
    return query.filter(
        department_column == current_user.department_id,
        model.organization_id == organization_id,
    )


def assert_record_scope(user: User, record, *, allow_officer_read: bool = False) -> None:
    """Authorize both department and organization; missing ownership denies access."""
    user = ensure_account_ready_for_app(user)
    assert_department_scope(user, record.department_id, allow_officer_read=allow_officer_read)
    if user.role == "super_admin":
        return
    organization_id = getattr(user, "organization_id", None)
    if organization_id is None or organization_id != getattr(record, "organization_id", None):
        raise HTTPException(status_code=403, detail="You can only access records in your assigned organization")


def ensure_operational_assignment(user: User) -> None:
    """Even operations without a loaded record require a complete assignment."""
    if user.role in {"admin", "adviser", "treasurer", "officer"} and (
        getattr(user, "department_id", None) is None
        or getattr(user, "organization_id", None) is None
    ):
        raise HTTPException(status_code=403, detail="An administrator must assign your department and organization")


def resolve_organization_id(
    db: Session, user: User, requested_id: uuid.UUID | None, department_id: uuid.UUID | None,
) -> uuid.UUID:
    """Resolve an existing organization and verify its parent department."""
    if user.role != "super_admin":
        assigned_id = getattr(user, "organization_id", None)
        if assigned_id is None or (requested_id is not None and requested_id != assigned_id):
            raise HTTPException(status_code=403, detail="Use your assigned organization")
        requested_id = assigned_id
    if requested_id is None:
        raise HTTPException(status_code=400, detail="organization_id is required")
    organization = db.query(Organization).filter(Organization.id == requested_id).first()
    if organization is None or organization.department_id != department_id:
        raise HTTPException(status_code=400, detail="Organization must exist in the selected department")
    return organization.id


def resolve_department_id(
    current_user: User,
    requested_department_id: uuid.UUID | None,
    *,
    require_for_admin: bool = False,
) -> uuid.UUID | None:
    """Resolve and validate a department id for a newly-created record.

    Scoped users and Admins can only create records in their own department.
    Super Admins may choose a department, and optionally may create an
    intentionally global record when ``require_for_admin`` is false.
    """
    current_user = ensure_account_ready_for_app(current_user)
    if current_user.role == "super_admin":
        if require_for_admin and requested_department_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="department_id is required when an admin creates this record.",
            )
        return requested_department_id

    if current_user.department_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account has no department assigned. Contact an administrator.",
        )
    if (
        requested_department_id is not None
        and requested_department_id != current_user.department_id
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only create records in your own department.",
        )
    return current_user.department_id
