"""
Shared FastAPI dependencies. `get_current_user` is the one every
protected route will use — it reads the "Authorization: Bearer <token>"
header, decodes it, and loads the matching User row.

`require_role(...)` builds on top of it for routes that should only be
usable by certain roles (e.g. only admins can create categories).
"""

import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User
from app.security import decode_access_token

# tokenUrl just tells FastAPI's auto-docs (/docs) where to send the
# "Authorize" button's login request — it doesn't affect behavior here.
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
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

    if user is None or not user.is_active:
        raise credentials_exception

    return user


def require_role(*allowed_roles: str):
    """
    Usage in a route:
        @router.post("/categories")
        def create_category(user: User = Depends(require_role("admin"))):
            ...
    """

    def role_checker(user: User = Depends(get_current_user)) -> User:
        if user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Requires one of these roles: {', '.join(allowed_roles)}",
            )
        return user

    return role_checker
