"""Account provisioning participates in the caller's transaction."""

import secrets
from uuid import UUID

from sqlalchemy.orm import Session

from app.models import User
from app.security import hash_password
from app.services.email import send_otp_email
from app.services.otp import add_otp_token, can_issue_otp, generate_otp_code


def create_unverified_user_with_otp(
    db: Session,
    *,
    full_name: str,
    email: str,
    password: str,
    role: str,
    position: str | None = None,
    department_id: UUID | None = None,
    organization_id: UUID | None = None,
) -> User:
    user = User(
        full_name=full_name,
        email=email.strip().lower(),
        password_hash=hash_password(password),
        role=role,
        position=position,
        department_id=department_id,
        organization_id=organization_id,
        is_active=False,
        must_change_password=False,
    )
    db.add(user)
    db.flush()
    otp_code = generate_otp_code()
    add_otp_token(db, user.id, "registration", otp_code)
    send_otp_email(email, full_name, otp_code, purpose="registration")
    return user


def create_user_with_temp_password(
    db: Session,
    *,
    full_name: str,
    email: str,
    role: str,
    position: str | None = None,
    department_id: UUID | None = None,
    organization_id: UUID | None = None,
) -> User:
    temporary_password = secrets.token_urlsafe(24)
    user = User(
        full_name=full_name,
        email=email.strip().lower(),
        password_hash=hash_password(temporary_password),
        role=role,
        position=position,
        department_id=department_id,
        organization_id=organization_id,
        must_change_password=True,
    )
    db.add(user)
    db.flush()
    add_otp_token(db, user.id, "initial_setup", temporary_password)
    send_otp_email(email, full_name, temporary_password, purpose="initial_setup")
    return user


def issue_password_reset_otp(db: Session, user: User) -> None:
    if not can_issue_otp(db, user.id, "password_reset"):
        return
    otp_code = generate_otp_code()
    add_otp_token(db, user.id, "password_reset", otp_code)
    send_otp_email(user.email, user.full_name, otp_code, purpose="password_reset")
