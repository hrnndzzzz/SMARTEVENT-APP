"""
Account creation, login, and the full OTP-based password lifecycle.

Self-registration uses a chosen password and an email verification OTP.
Administrator-provisioned accounts instead use a temporary password:

  1. POST /auth/register       — CITE self-registration. Public, no
     token required. Validates the submitted email against the
     pre-approved cite_members roster (see routers/cite_members.py)
     and auto-assigns the role/full_name recorded there — the caller
     cannot choose their own role. This REPLACES the old admin-only
     registration entirely.

  2. POST /auth/register/sds   — a super_admin creates an SDS
     Department account. SDS has no roster/list concept like CITE
     does, so an existing super_admin creates these directly.

  3. scripts/create_super_admin.py — a CLI script, not an HTTP route
     at all. Run locally/on-server by whoever has direct database
     access (e.g. future IT staff). This is the "manual account
     creation interface" for Super Admin — no bootstrap-permission
     problem, since it never goes through the API's own auth layer.

Self-registration is automatically approved only after roster eligibility
and email verification pass. Provisioned accounts must change their
temporary password after their first login.
"""

import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.dependencies import get_current_user, require_active_account, require_role, resolve_organization_id
from app.models import CiteMember, Department, OtpToken, User
from app.schemas import (
    AdminRegisterRequest,
    ChangePasswordRequest,
    CiteSelfRegisterRequest,
    ForgotPasswordRequest,
    ResetPasswordRequest,
    SdsRegisterRequest,
    Token,
    UserOut,
    VerifyOtpRequest,
    RegistrationVerificationOut,
)
from app.security import create_access_token, hash_password, verify_password
from app.services.account_provisioning import (
    create_unverified_user_with_otp,
    create_user_with_temp_password,
    issue_password_reset_otp,
)
from app.services.email import EmailError, send_otp_email
from app.services.access_audit import record_access_change
from app.services.otp import generate_otp_code, hash_otp_code, verify_otp_code
from app.services.notifications import check_registration_assignment, queue_registration_confirmation, deliver_notification

router = APIRouter(prefix="/auth", tags=["auth"])


def _expired(value):
    value = value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)
    return value <= datetime.now(timezone.utc)


@router.get("/permissions")
def read_permissions(current_user: User = Depends(require_active_account)):
    from app.rbac_policy import ROLE_POLICY
    return {"role": current_user.role, **ROLE_POLICY[current_user.role]}


@router.post("/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def register(payload: CiteSelfRegisterRequest, db: Session = Depends(get_db)):
    """
    CITE self-registration. The submitted email must already be on the
    cite_members roster (added there by an administrator beforehand via
    POST /cite-members) — full_name, role, and position all come from
    that roster entry, never from what the caller types.

    The user supplies their chosen password. The account is created in an
    inactive/unverified state (is_active=False) and an OTP is emailed to
    verify registration. The user must verify via POST /auth/verify-otp
    before logging in.
    """
    member = db.query(CiteMember).filter(CiteMember.email == payload.email).with_for_update().first()
    if member is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "This email is not on the CITE member roster. "
                "Contact an administrator to be added before registering."
            ),
        )
    check_registration_assignment(db, member)
    if member.claimed_by_user_id is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This CITE roster entry has already been used to create an account.",
        )

    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email already exists",
        )

    try:
        user = create_unverified_user_with_otp(
            db,
            full_name=member.full_name,
            email=member.email,
            password=payload.password,
            role=member.role,
            position=member.position,
            department_id=member.department_id,
            organization_id=member.organization_id,
        )
        # Carry the roster's department assignment onto the user account
        # so enforce_department_scope can use it for scoped routes.
        user.department_id = member.department_id
        user.organization_id = member.organization_id
        member.claimed_by_user_id = user.id
        db.commit()
    except (RuntimeError, EmailError) as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))

    db.refresh(user)
    return user


@router.post("/verify-otp", response_model=RegistrationVerificationOut)
def verify_otp(payload: VerifyOtpRequest, db: Session = Depends(get_db)):
    """
    Verifies the one-time registration code emailed during self-registration
    and activates the account (sets is_active=True).
    """
    user = db.query(User).filter(User.email == payload.email).with_for_update().first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid email or code",
        )

    if user.is_suspended:
        raise HTTPException(status_code=403, detail="This account is suspended. Contact an administrator.")
    if user.is_active:
        return {"detail": "Account is already verified and active. You can log in."}

    token = (
        db.query(OtpToken)
        .filter(
            OtpToken.user_id == user.id,
            OtpToken.purpose == "registration",
            OtpToken.used_at.is_(None),
        )
        .order_by(OtpToken.created_at.desc())
        .with_for_update()
        .first()
    )

    if token is None or _expired(token.expires_at):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Verification code has expired. Please request a new code.",
        )

    if not verify_otp_code(payload.otp_code, token.code_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid verification code",
        )

    member = db.query(CiteMember).filter(CiteMember.email == user.email).with_for_update().first()
    if member is None:
        raise HTTPException(403, "Registration is no longer on the approved roster. Contact an administrator.")
    check_registration_assignment(db, member, user)
    token.used_at = datetime.now(timezone.utc)
    user.is_active = True
    notification = queue_registration_confirmation(db, user)
    record_access_change(db, user, "user.registration_approved", user)
    db.commit()
    notification_id = notification.id
    deliver_notification(db, notification_id)
    db.refresh(notification)

    return {"detail": "Account successfully verified and automatically approved. You can now log in.",
            "registration_status": "approved", "notification_id": str(notification_id),
            "confirmation_email_status": notification.email_status}


@router.post("/resend-otp")
def resend_otp(payload: ForgotPasswordRequest, db: Session = Depends(get_db)):
    """
    Resends an OTP verification code if the user registered but has not yet verified.
    """
    user = db.query(User).filter(User.email == payload.email).with_for_update().first()
    if user is not None and not user.is_active and not user.is_suspended:
        otp_code = generate_otp_code()
        for previous in db.query(OtpToken).filter(
            OtpToken.user_id == user.id, OtpToken.purpose == "registration",
            OtpToken.used_at.is_(None),
        ).all():
            previous.used_at = datetime.now(timezone.utc)
        db.add(
            OtpToken(
                user_id=user.id,
                purpose="registration",
                code_hash=hash_otp_code(otp_code),
                expires_at=datetime.now(timezone.utc)
                + timedelta(minutes=settings.otp_expiry_minutes),
            )
        )
        try:
            send_otp_email(user.email, user.full_name, otp_code, purpose="registration")
            db.commit()
        except (RuntimeError, EmailError):
            db.rollback()

    return {"detail": "If that email is pending registration, a new verification code has been sent."}


@router.post("/register/admin", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def register_admin(
    payload: AdminRegisterRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("super_admin")),
):
    """A super_admin creates an Admin account scoped to the selected department."""
    department = db.query(Department).filter(Department.id == payload.department_id).first()
    if department is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="department_id does not match any existing department",
        )

    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email already exists",
        )

    organization_id = resolve_organization_id(db, current_user, payload.organization_id, department.id)
    try:
        user = create_user_with_temp_password(
            db,
            full_name=payload.full_name,
            email=payload.email,
            role="admin",
            position=payload.position,
            department_id=department.id,
            organization_id=organization_id,
        )
        user.department_id = department.id
        user.organization_id = organization_id
        record_access_change(db, current_user, "user.admin_created", user)
        db.commit()
    except (RuntimeError, EmailError) as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))

    db.refresh(user)
    return user


@router.post("/register/sds", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def register_sds(
    payload: SdsRegisterRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("super_admin")),
):
    """A super_admin creates an SDS Department account (view-only role — see routers/proposal_letters.py)."""
    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email already exists",
        )

    try:
        user = create_user_with_temp_password(
            db,
            full_name=payload.full_name,
            email=payload.email,
            role="sds_staff",
            position=payload.position,
        )
        record_access_change(db, current_user, "user.sds_created", user)
        db.commit()
    except (RuntimeError, EmailError) as exc:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))

    db.refresh(user)
    return user


@router.post("/login", response_model=Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    # OAuth2PasswordRequestForm sends the email in its `username` field —
    # standard OAuth2 form shape, not a schema mismatch.
    user = db.query(User).filter(User.email == form_data.username).first()

    if not user or not verify_password(form_data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not user.is_active or user.is_suspended:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is unverified or has been deactivated. Please verify your registration OTP code or contact an administrator.",
        )

    if user.must_change_password:
        # The password that just verified successfully IS the OTP —
        # but OTPs expire. Check whether it's still within its window;
        # if the user never logged in in time, block login even though
        # the password technically matches, rather than allow an
        # indefinitely-valid "temporary" password.
        active_otp = (
            db.query(OtpToken)
            .filter(
                OtpToken.user_id == user.id,
                OtpToken.purpose == "initial_setup",
                OtpToken.used_at.is_(None),
            )
            .order_by(OtpToken.created_at.desc())
            .first()
        )
        if active_otp is None or _expired(active_otp.expires_at):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=(
                    "Your temporary password has expired. Contact an "
                    "administrator to reissue your account."
                ),
            )

    access_token = create_access_token(subject=str(user.id))
    return Token(access_token=access_token)


@router.get("/me", response_model=UserOut)
def read_current_user(current_user: User = Depends(require_active_account)):
    return current_user


@router.post("/change-password", response_model=UserOut)
def change_password(
    payload: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Works whether current_password is the emailed OTP (first login) or
    an already-real password (routine change later) — both are just
    verified against password_hash the normal way.
    """
    if not verify_password(payload.current_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect",
        )

    current_user.password_hash = hash_password(payload.new_password)
    current_user.must_change_password = False

    # Mark any still-active initial_setup OTP as used, for a clean
    # audit trail — not strictly required for login to keep working
    # (must_change_password=False already bypasses the OTP-expiry
    # check above), but avoids a stale "active" token lingering.
    active_otp = (
        db.query(OtpToken)
        .filter(
            OtpToken.user_id == current_user.id,
            OtpToken.purpose == "initial_setup",
            OtpToken.used_at.is_(None),
        )
        .first()
    )
    if active_otp is not None:
        active_otp.used_at = datetime.now(timezone.utc)

    db.commit()
    db.refresh(current_user)
    return current_user


@router.post("/forgot-password")
def forgot_password(payload: ForgotPasswordRequest, db: Session = Depends(get_db)):
    """
    Always returns the same generic response regardless of whether the
    email is registered — this is deliberate, to avoid letting someone
    probe which emails have accounts (account enumeration). The actual
    email only gets sent if a matching, active user exists.
    """
    user = db.query(User).filter(User.email == payload.email).first()
    if user is not None and user.is_active:
        try:
            issue_password_reset_otp(db, user)
            db.commit()
        except (RuntimeError, EmailError):
            # Failure is swallowed from the caller's perspective on
            # purpose (see docstring) — still logged server-side via
            # the exception itself if you have logging configured.
            db.rollback()

    return {"detail": "If that email is registered, a password reset code has been sent."}


@router.post("/reset-password")
def reset_password(payload: ResetPasswordRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()

    # Generic "invalid or expired code" for both "no such user" and
    # "wrong/expired code" — same account-enumeration reasoning as
    # forgot-password above.
    invalid_response = HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail="Invalid or expired code",
    )

    if user is None:
        raise invalid_response

    token = (
        db.query(OtpToken)
        .filter(
            OtpToken.user_id == user.id,
            OtpToken.purpose == "password_reset",
            OtpToken.used_at.is_(None),
        )
        .order_by(OtpToken.created_at.desc())
        .first()
    )
    if token is None or _expired(token.expires_at):
        raise invalid_response
    if not verify_otp_code(payload.otp_code, token.code_hash):
        raise invalid_response

    user.password_hash = hash_password(payload.new_password)
    user.must_change_password = False
    token.used_at = datetime.now(timezone.utc)
    db.commit()

    return {"detail": "Password reset successful. You can now log in with your new password."}
