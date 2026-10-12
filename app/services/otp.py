"""One-time codes expire, are replaced on resend, and permit five guesses."""

import secrets
from datetime import datetime, timedelta, timezone

from app.config import settings
from app.models import OtpToken
from app.security import hash_password, verify_password


def generate_otp_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def hash_otp_code(code: str) -> str:
    return hash_password(code)


def verify_otp_code(code: str, code_hash: str) -> bool:
    return verify_password(code, code_hash)


def is_expired(value) -> bool:
    value = value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)
    return value <= datetime.now(timezone.utc)


def invalidate_otp_tokens(db, user_id, purpose=None) -> None:
    query = db.query(OtpToken).filter(OtpToken.user_id == user_id, OtpToken.used_at.is_(None))
    if purpose is not None:
        query = query.filter(OtpToken.purpose == purpose)
    query.update({OtpToken.used_at: datetime.now(timezone.utc)}, synchronize_session="fetch")


def add_otp_token(db, user_id, purpose, code) -> None:
    invalidate_otp_tokens(db, user_id, purpose)
    db.add(OtpToken(
        user_id=user_id,
        purpose=purpose,
        code_hash=hash_otp_code(code),
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=settings.otp_expiry_minutes),
    ))


def can_issue_otp(db, user_id, purpose) -> bool:
    latest = db.query(OtpToken).filter(
        OtpToken.user_id == user_id, OtpToken.purpose == purpose,
    ).order_by(OtpToken.created_at.desc()).first()
    if latest is None:
        return True
    created_at = latest.created_at
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc) - created_at >= timedelta(minutes=1)


def verify_otp_token(db, token, code, *, allow_used=False) -> bool:
    if (token is None or (token.used_at is not None and not allow_used)
            or is_expired(token.expires_at) or token.failed_attempts >= 5):
        return False
    if verify_otp_code(code, token.code_hash):
        return True
    token.failed_attempts += 1
    if token.failed_attempts >= 5:
        token.used_at = datetime.now(timezone.utc)
    db.commit()
    return False
