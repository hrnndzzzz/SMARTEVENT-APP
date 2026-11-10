"""Shared authentication and fail-closed authorization."""

import uuid
from datetime import timezone

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Organization, User
from app.rbac_policy import FINANCIAL_ROLES, can_propose_events, can_record_finance
from app.security import decode_access_token


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")


VALID_ROLES = {
    "super_admin",
    "admin",
    "adviser",
    "treasurer",
    "officer",
    "sds_staff",
    "signatory",
}
ADMIN_ROLES = {"admin", "super_admin"}
SCOPED_OPERATIONAL_ROLES = {"adviser", "treasurer"}
SCOPED_READ_ROLES = SCOPED_OPERATIONAL_ROLES | {"officer"}

# Match registered route templates so future endpoints never inherit an exception.
OFFICER_PROPOSAL_WRITES = {
    ("POST", "/events"),
    ("PATCH", "/events/{event_id}"),
    ("DELETE", "/events/{event_id}"),
    ("POST", "/events/{event_id}/submit"),
    ("POST", "/proposal-letters"),
    ("POST", "/events/{event_id}/sap-proposal"),
    ("PATCH", "/events/{event_id}/sap-proposal"),
    ("PUT", "/events/{event_id}/sap-proposal/{collection}"),
    ("POST", "/events/{event_id}/sap-proposal/attachments"),
    ("POST", "/events/{event_id}/sap-proposal/submit"),
    ("POST", "/events/{event_id}/sap-proposal/withdraw"),
}
# Any officer may be tasked with handing out or returning stock.
OFFICER_INVENTORY_WRITES = {
    ("POST", "/inventory/{inventory_id}/transactions"), ("POST", "/inventory"), ("DELETE", "/inventory/{inventory_id}"),
}
# Officers record money like the Treasurer; reviewing it stays with advisers and admins.
OFFICER_FINANCE_WRITES = {
    ("POST", "/incomes"),
    ("POST", "/expenses"),
    ("PATCH", "/expenses/{expense_id}"),
    ("DELETE", "/expenses/{expense_id}"),
    ("POST", "/expenses/scan-receipt"),
    ("POST", "/expenses/{expense_id}/receipt"),
    ("POST", "/expenses/{expense_id}/parse-receipt"),
    ("POST", "/expenses/{expense_id}/complete-purchase"),
    ("POST", "/receipts"),
    ("POST", "/receipts/{receipt_id}/upload"),
}


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    claims = decode_access_token(token)
    if claims is None:
        raise credentials_exception

    try:
        user = db.query(User).filter(User.id == uuid.UUID(claims["sub"])).first()
    except (ValueError, TypeError, AttributeError):
        raise credentials_exception

    if user is None or not user.is_active or user.is_suspended:
        raise credentials_exception

    if user.role not in VALID_ROLES:
        raise credentials_exception

    updated_at = user.updated_at
    if updated_at is not None:
        if updated_at.tzinfo is None:
            updated_at = updated_at.replace(tzinfo=timezone.utc)
        if claims["iat"] < updated_at.timestamp():
            raise credentials_exception

    return user


def require_active_account(user: User = Depends(get_current_user)) -> User:
    if user.must_change_password:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Password change required before accessing this resource",
        )
    return user


def ensure_account_ready_for_app(user: User) -> User:
    if getattr(user, "is_suspended", False):
        raise HTTPException(status_code=403, detail="This account is suspended")
    if getattr(user, "must_change_password", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Password change required before accessing this resource",
        )
    return user


def require_role(*allowed_roles: str):
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
    """Officer writes are limited to explicitly authorized proposal, inventory and finance routes."""
    user = ensure_account_ready_for_app(user)
    if user.role == "officer" and request.method not in ("GET", "HEAD", "OPTIONS"):
        route = request.scope.get("route")
        write = (request.method, getattr(route, "path", None))
        if (write in OFFICER_INVENTORY_WRITES or write in OFFICER_FINANCE_WRITES
                or (can_propose_events(user) and write in OFFICER_PROPOSAL_WRITES)):
            return user
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Role '{user.role}' has read-only access. {request.method} requests are forbidden.",
        )
    return user


def require_event_proposer(user: User = Depends(require_active_account)) -> User:
    user = ensure_account_ready_for_app(user)
    ensure_operational_assignment(user)
    if not can_propose_events(user):
        raise HTTPException(status_code=403, detail="Your role and position do not permit event proposals")
    return user


def require_financial_access(
    user: User = Depends(require_active_account),
) -> User:
    """Financial recording belongs to officers and the Treasurer, never their reviewers."""
    user = ensure_account_ready_for_app(user)
    ensure_operational_assignment(user)
    if not can_record_finance(user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Financial recording is restricted to officers and the treasurer",
        )
    return user


def require_proposal_letter_reader(user: User = Depends(require_active_account)) -> User:
    user = ensure_account_ready_for_app(user)
    ensure_operational_assignment(user)
    if user.role in {"sds_staff", "signatory"}:
        return user
    return require_event_proposer(user)


def require_operational_read(
    user: User = Depends(require_active_account),
) -> User:
    user = ensure_account_ready_for_app(user)
    ensure_operational_assignment(user)
    if user.role not in ADMIN_ROLES | SCOPED_READ_ROLES:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This role has no access to operational data",
        )
    return user


def is_departmentless(user) -> bool:
    """A member of an organization that belongs to no department.

    Both sides must be blank: an account left without a department in an
    organization that has one is unassigned, not department-less.
    """
    organization = getattr(user, "organization", None)
    return (
        getattr(user, "role", None) in SCOPED_READ_ROLES
        and getattr(user, "department_id", None) is None
        and getattr(user, "organization_id", None) is not None
        and organization is not None
        and organization.department_id is None
    )


def assert_department_scope(
    user: User,
    record_department_id: uuid.UUID | None,
    *,
    allow_officer_read: bool = False,
) -> None:
    if user.role == "super_admin":
        return

    allowed_roles = (SCOPED_READ_ROLES | {"admin"}) if allow_officer_read else (SCOPED_OPERATIONAL_ROLES | {"admin"})
    if user.role not in allowed_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Role '{user.role}' is not permitted to access this scoped record",
        )

    if is_departmentless(user):
        if record_department_id is not None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only access records belonging to your own organization.",
            )
        return

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


def assert_owner_or_admin(
    owner_id: uuid.UUID,
    current_user: User,
    action: str,
    *,
    owner_roles: set[str] = SCOPED_OPERATIONAL_ROLES,
) -> None:
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

    Super Admins retain global visibility. Admins see assigned records across
    their department; other operational readers see only their organization.
    Both account assignments are required. This helper is for models such as ``Event`` and
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
    if is_departmentless(current_user):
        return query.filter(
            department_column.is_(None),
            department_column.class_.organization_id == current_user.organization_id,
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
    if current_user.role == "admin":
        return query.filter(department_column == current_user.department_id, model.organization_id.is_not(None))
    return query.filter(
        department_column == current_user.department_id,
        model.organization_id == organization_id,
    )


def assert_record_scope(user: User, record, *, allow_officer_read: bool = False) -> None:
    """Admins span their department; members stay in their own organization."""
    user = ensure_account_ready_for_app(user)
    assert_department_scope(user, record.department_id, allow_officer_read=allow_officer_read)
    if user.role == "super_admin":
        return
    if getattr(record, "organization_id", None) is None:
        raise HTTPException(status_code=403, detail="This record has no organization assigned")
    if user.role == "admin":
        return
    organization_id = getattr(user, "organization_id", None)
    if organization_id is None or organization_id != getattr(record, "organization_id", None):
        raise HTTPException(status_code=403, detail="You can only access records in your assigned organization")


def ensure_operational_assignment(user: User) -> None:
    if user.role not in {"admin", "adviser", "treasurer", "officer"}:
        return
    if getattr(user, "organization_id", None) is None or (
        getattr(user, "department_id", None) is None and not is_departmentless(user)
    ):
        raise HTTPException(status_code=403, detail="An administrator must assign your department and organization")
    # Failsafe: the account's department must be its organization's, never blank beside one.
    organization = getattr(user, "organization", None)
    if organization is not None and organization.department_id != user.department_id:
        raise HTTPException(status_code=403, detail="An administrator must assign your department and organization")


def resolve_organization_id(
    db: Session, user: User, requested_id: uuid.UUID | None, department_id: uuid.UUID | None,
) -> uuid.UUID:
    """Resolve an existing organization and verify its parent department."""
    if user.role == "admin":
        ensure_operational_assignment(user)
        requested_id = requested_id or user.organization_id
        if department_id != user.department_id:
            raise HTTPException(status_code=403, detail="Use your assigned department")
    elif user.role != "super_admin":
        assigned_id = getattr(user, "organization_id", None)
        if assigned_id is None or (requested_id is not None and requested_id != assigned_id):
            raise HTTPException(status_code=403, detail="Use your assigned organization")
        requested_id = assigned_id
    if requested_id is None:
        raise HTTPException(status_code=400, detail="organization_id is required")
    organization = db.query(Organization).filter(Organization.id == requested_id).first()
    if organization is not None and user.role == "admin" and organization.department_id != user.department_id:
        raise HTTPException(status_code=403, detail="Use an organization in your assigned department")
    if organization is not None and department_id is None and organization.department_id is not None:
        raise HTTPException(status_code=400, detail="This organization belongs to a department. Select it.")
    if organization is None or organization.department_id != department_id:
        raise HTTPException(status_code=400, detail="Organization must exist in the selected department")
    return organization.id


def resolve_department_id(
    current_user: User,
    requested_department_id: uuid.UUID | None,
    *,
    require_for_admin: bool = False,
) -> uuid.UUID | None:
    current_user = ensure_account_ready_for_app(current_user)
    if current_user.role == "super_admin":
        # Blank is allowed: resolve_organization_id, which every caller runs next,
        # refuses it unless the chosen organization has no department.
        return requested_department_id

    if is_departmentless(current_user):
        if requested_department_id is not None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Your organization belongs to no department.",
            )
        return None

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
