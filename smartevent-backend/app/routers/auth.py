"""Registration, login, and password recovery."""

import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from app.database import get_db
from app.dependencies import VALID_ROLES, get_current_user, require_active_account, require_role, resolve_organization_id
from app.config import settings
from app.models import CiteMember, Department, OtpToken, RefreshToken, User
from app.schemas import (
    AdminRegisterRequest,
    ChangePasswordRequest,
    CiteSelfRegisterRequest,
    ForgotPasswordRequest,
    RefreshRequest,
    ResetPasswordRequest,
    SdsRegisterRequest,
    SignatoryRegisterRequest,
    Token,
    UserOut,
    VerifyOtpRequest,
    RegistrationVerificationOut,
)
from app.security import create_access_token, hash_password, hash_refresh_token, new_refresh_token, verify_password
from app.services.account_provisioning import (
    create_unverified_user_with_otp,
    create_user_with_temp_password,
    issue_password_reset_otp,
)
from app.services.email import EmailError, send_otp_email
from app.services.access_audit import record_access_change
from app.services.otp import add_otp_token, can_issue_otp, generate_otp_code, invalidate_otp_tokens, is_expired, verify_otp_token
from app.services.notifications import check_registration_assignment, queue_registration_confirmation, deliver_notification

router = APIRouter(prefix="/auth", tags=["auth"])
logger = logging.getLogger(__name__)
_dummy_password_hash = hash_password("invalid-account-password")


@router.get("/permissions")
def read_permissions(current_user: User = Depends(require_active_account)):
    from app.rbac_policy import effective_role_policy
    return effective_role_policy(current_user)


@router.post("/register", status_code=status.HTTP_201_CREATED)
def register(payload: CiteSelfRegisterRequest, db: Session = Depends(get_db)):
    member = db.query(CiteMember).filter(func.lower(CiteMember.email) == payload.email.lower()).with_for_update().first()
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

    existing = db.query(User).filter(func.lower(User.email) == payload.email.lower()).first()
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
        member.claimed_by_user_id = user.id
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="An account for this email already exists")
    except (RuntimeError, EmailError):
        db.rollback()
        logger.warning("Registration email delivery failed")
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Account email delivery is unavailable. Try again later.")

    return {"detail": "Check your email for a registration verification code.", "is_active": False}


@router.post("/verify-otp", response_model=RegistrationVerificationOut)
def verify_otp(payload: VerifyOtpRequest, db: Session = Depends(get_db)):
    invalid_response = HTTPException(status_code=400, detail="Invalid email or code")
    user = db.query(User).filter(func.lower(User.email) == payload.email.lower()).with_for_update().first()
    if user is None or user.is_suspended:
        raise invalid_response
    query = db.query(OtpToken).filter(
        OtpToken.user_id == user.id, OtpToken.purpose == "registration",
    )
    if not user.is_active:
        query = query.filter(OtpToken.used_at.is_(None))
    token = query.order_by(OtpToken.created_at.desc()).with_for_update().first()
    if not verify_otp_token(db, token, payload.otp_code, allow_used=user.is_active):
        raise invalid_response
    if user.is_active:
        return {"detail": "Account is already verified and active. You can log in."}

    member = db.query(CiteMember).filter(func.lower(CiteMember.email) == user.email.lower()).with_for_update().first()
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
    user = db.query(User).filter(func.lower(User.email) == payload.email.lower()).with_for_update().first()
    if (user is not None and not user.is_active and not user.is_suspended
            and can_issue_otp(db, user.id, "registration")):
        otp_code = generate_otp_code()
        add_otp_token(db, user.id, "registration", otp_code)
        try:
            send_otp_email(user.email, user.full_name, otp_code, purpose="registration")
            db.commit()
        except (RuntimeError, EmailError):
            db.rollback()
            logger.warning("Registration verification email delivery failed")

    return {"detail": "If that email is pending registration, a new verification code has been sent."}


@router.post("/register/admin", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def register_admin(
    payload: AdminRegisterRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("super_admin")),
):
    department = db.query(Department).filter(Department.id == payload.department_id).first()
    if department is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="department_id does not match any existing department",
        )

    existing = db.query(User).filter(func.lower(User.email) == payload.email.lower()).first()
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
        record_access_change(db, current_user, "user.admin_created", user)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="An account for this email already exists")
    except (RuntimeError, EmailError):
        db.rollback()
        logger.warning("Admin account email delivery failed")
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Account email delivery is unavailable. Try again later.")

    db.refresh(user)
    return user


@router.post("/register/sds", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def register_sds(
    payload: SdsRegisterRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("super_admin")),
):
    return _register_school_reviewer(payload, "sds_staff", "user.sds_created", db, current_user)


@router.post("/register/signatory", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def register_signatory(
    payload: SignatoryRegisterRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("super_admin")),
):
    return _register_school_reviewer(payload, "signatory", "user.signatory_created", db, current_user)


def _register_school_reviewer(payload, role, action, db, current_user):
    existing = db.query(User).filter(func.lower(User.email) == payload.email.lower()).first()
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
            role=role,
            position=payload.position,
        )
        record_access_change(db, current_user, action, user)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="An account for this email already exists")
    except (RuntimeError, EmailError):
        db.rollback()
        logger.warning("School reviewer account email delivery failed")
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Account email delivery is unavailable. Try again later.")

    db.refresh(user)
    return user


@router.post("/login", response_model=Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    invalid_credentials = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Incorrect email or password",
        headers={"WWW-Authenticate": "Bearer"},
    )
    email = form_data.username.strip().lower()
    if not email or len(email) > 150 or not 1 <= len(form_data.password) <= 128:
        raise invalid_credentials
    user = db.query(User).filter(func.lower(User.email) == email).with_for_update().first()
    if user is None:
        verify_password(form_data.password, _dummy_password_hash)
        raise invalid_credentials
    if user.login_locked_until is not None:
        if not is_expired(user.login_locked_until):
            raise invalid_credentials
        user.login_failed_attempts = 0
        user.login_locked_until = None
    if not verify_password(form_data.password, user.password_hash):
        user.login_failed_attempts += 1
        if user.login_failed_attempts >= 5:
            user.login_locked_until = datetime.now(timezone.utc) + timedelta(minutes=15)
        db.commit()
        raise invalid_credentials

    if not user.is_active or user.is_suspended or user.role not in VALID_ROLES:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is unverified or has been deactivated. Please verify your registration OTP code or contact an administrator.",
        )

    if user.must_change_password:
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
        if active_otp is None or is_expired(active_otp.expires_at):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=(
                    "Your temporary password has expired. Contact an "
                    "administrator to reissue your account."
                ),
            )

    user.login_failed_attempts = 0
    user.login_locked_until = None
    # A temporary password gets no renewal key: that session stays short.
    renewal = None if user.must_change_password else _issue_refresh_token(db, user)
    db.commit()
    access_token = create_access_token(subject=str(user.id))
    return Token(access_token=access_token, must_change_password=user.must_change_password, refresh_token=renewal)


def _issue_refresh_token(db, user) -> str | None:
    token, digest = new_refresh_token()
    try:
        with db.begin_nested():
            db.add(RefreshToken(user_id=user.id, token_hash=digest,
                                expires_at=datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_days)))
    except SQLAlchemyError:
        # Deployed before its migration: signing in still works, only without renewal.
        logger.warning("Could not issue a renewal key; apply pending database migrations")
        return None
    return token


def _revoke_refresh_tokens(db, user_id) -> None:
    try:
        with db.begin_nested():
            db.query(RefreshToken).filter(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None)).update(
                {RefreshToken.revoked_at: datetime.now(timezone.utc)}, synchronize_session=False)
    except SQLAlchemyError:
        # No table yet means no keys were ever issued, so there are none to end.
        logger.warning("Could not end renewal keys; apply pending database migrations")


@router.post("/refresh", response_model=Token)
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)):
    """Swaps the device's renewal key for a fresh access token, without the password.

    The key is not rotated: a reply lost on a weak connection must not cost the
    device its session. Its expiry moves forward instead. Signing out, a password
    change or reset, and a suspended or deactivated account all end it."""
    refused = HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Sign in again",
                            headers={"WWW-Authenticate": "Bearer"})
    row = db.query(RefreshToken).filter(
        RefreshToken.token_hash == hash_refresh_token(payload.refresh_token)).with_for_update().first()
    if row is None or row.revoked_at is not None or is_expired(row.expires_at):
        raise refused
    user = db.get(User, row.user_id)
    if (user is None or not user.is_active or user.is_suspended or user.must_change_password
            or user.role not in VALID_ROLES):
        row.revoked_at = datetime.now(timezone.utc)
        db.commit()
        raise refused
    row.expires_at = datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_days)
    db.commit()
    return Token(access_token=create_access_token(subject=str(user.id)), refresh_token=payload.refresh_token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(payload: RefreshRequest, db: Session = Depends(get_db)):
    """Ends this device's renewal key. Holding the key is the proof; an unknown one is a no-op."""
    db.query(RefreshToken).filter(RefreshToken.token_hash == hash_refresh_token(payload.refresh_token),
                                  RefreshToken.revoked_at.is_(None)).update(
        {RefreshToken.revoked_at: datetime.now(timezone.utc)}, synchronize_session=False)
    db.commit()


@router.get("/me", response_model=UserOut)
def read_current_user(current_user: User = Depends(require_active_account)):
    return current_user


@router.post("/change-password", response_model=UserOut)
def change_password(
    payload: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    current_user = db.query(User).filter(User.id == current_user.id).populate_existing().with_for_update().one()
    if not verify_password(payload.current_password, current_user.password_hash):
        # 400, not 401: the session is fine, and clients read 401 as signed out.
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current password is incorrect",
        )

    if current_user.must_change_password:
        active_otp = db.query(OtpToken).filter(
            OtpToken.user_id == current_user.id, OtpToken.purpose == "initial_setup",
            OtpToken.used_at.is_(None),
        ).with_for_update().first()
        if active_otp is None or is_expired(active_otp.expires_at):
            raise HTTPException(status_code=401, detail="Your temporary password has expired")
    current_user.password_hash = hash_password(payload.new_password)
    current_user.must_change_password = False
    current_user.updated_at = datetime.now(timezone.utc)
    current_user.login_failed_attempts = 0
    current_user.login_locked_until = None
    invalidate_otp_tokens(db, current_user.id)
    _revoke_refresh_tokens(db, current_user.id)  # every device signs in again with the new password
    record_access_change(db, current_user, "user.password_changed", current_user)

    db.commit()
    db.refresh(current_user)
    return current_user


@router.post("/forgot-password")
def forgot_password(payload: ForgotPasswordRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(func.lower(User.email) == payload.email.lower()).with_for_update().first()
    if user is not None and user.is_active and not user.is_suspended:
        try:
            issue_password_reset_otp(db, user)
            db.commit()
        except (RuntimeError, EmailError):
            db.rollback()
            logger.warning("Password reset email delivery failed")

    return {"detail": "If that email is registered, a password reset code has been sent."}


@router.post("/reset-password")
def reset_password(payload: ResetPasswordRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(func.lower(User.email) == payload.email.lower()).with_for_update().first()

    invalid_response = HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail="Invalid or expired code",
    )

    if user is None or not user.is_active or user.is_suspended:
        raise invalid_response

    token = (
        db.query(OtpToken)
        .filter(
            OtpToken.user_id == user.id,
            OtpToken.purpose == "password_reset",
            OtpToken.used_at.is_(None),
        )
        .order_by(OtpToken.created_at.desc())
        .with_for_update()
        .first()
    )
    if not verify_otp_token(db, token, payload.otp_code):
        raise invalid_response

    user.password_hash = hash_password(payload.new_password)
    user.must_change_password = False
    user.updated_at = datetime.now(timezone.utc)
    user.login_failed_attempts = 0
    user.login_locked_until = None
    invalidate_otp_tokens(db, user.id)
    _revoke_refresh_tokens(db, user.id)
    record_access_change(db, user, "user.password_reset", user)
    db.commit()

    return {"detail": "Password reset successful. You can now log in with your new password."}
