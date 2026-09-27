"""
Shared logic for the OTP-based account lifecycle — used by all three
account-creation paths (CITE self-registration, super-admin-created
SDS accounts, the create_super_admin CLI script) plus the
forgot-password flow. Keeping this in one place means all of them
behave identically (same expiry window, same email wording, same
must_change_password handling) instead of drifting apart.

Neither function here commits — the caller commits (or rolls back on
email failure), so these can participate in a larger transaction.
"""

from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.config import settings
from app.models import OtpToken, User
from app.security import hash_password
from app.services.email import send_otp_email
from app.services.otp import generate_otp_code, hash_otp_code


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
    """
    Creates an unverified User (is_active=False, must_change_password=False)
    with the user's chosen password, generates an OTP (purpose='registration'),
    and emails it to the user. The account is activated once verified via
    POST /auth/verify-otp.
    """
    otp_code = generate_otp_code()

    user = User(
        full_name=full_name,
        email=email,
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

    db.add(
        OtpToken(
            user_id=user.id,
            purpose="registration",
            code_hash=hash_otp_code(otp_code),
            expires_at=datetime.now(timezone.utc)
            + timedelta(minutes=settings.otp_expiry_minutes),
        )
    )

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
    """
    Creates a User with a fresh OTP as its password (must_change_password
    = True), emails that OTP, and records an OtpToken (purpose=
    'initial_setup') tracking its expiry.

    Raises whatever send_otp_email raises (RuntimeError if Resend isn't
    configured, EmailError if sending fails) — the caller is expected
    to catch this, roll back the session, and return a clean error
    rather than silently leaving an account whose only password was
    never actually delivered to anyone.
    """
    otp_code = generate_otp_code()

    user = User(
        full_name=full_name,
        email=email,
        password_hash=hash_password(otp_code),
        role=role,
        position=position,
        department_id=department_id,
        organization_id=organization_id,
        must_change_password=True,
    )
    db.add(user)
    db.flush()  # assigns user.id for the OtpToken FK below

    db.add(
        OtpToken(
            user_id=user.id,
            purpose="initial_setup",
            code_hash=hash_otp_code(otp_code),
            expires_at=datetime.now(timezone.utc)
            + timedelta(minutes=settings.otp_expiry_minutes),
        )
    )

    send_otp_email(email, full_name, otp_code, purpose="initial_setup")

    return user


def issue_password_reset_otp(db: Session, user: User) -> None:
    """
    Generates a password-reset code, stores its hash (purpose=
    'password_reset'), and emails it. Does NOT touch user.password_hash
    — that only changes once the code is verified in
    POST /auth/reset-password. Same raise-on-email-failure contract as
    create_user_with_temp_password above.
    """
    otp_code = generate_otp_code()

    db.add(
        OtpToken(
            user_id=user.id,
            purpose="password_reset",
            code_hash=hash_otp_code(otp_code),
            expires_at=datetime.now(timezone.utc)
            + timedelta(minutes=settings.otp_expiry_minutes),
        )
    )

    send_otp_email(user.email, user.full_name, otp_code, purpose="password_reset")
