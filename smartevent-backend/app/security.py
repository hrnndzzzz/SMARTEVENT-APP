"""Argon2 password hashing and signed, expiring access tokens."""

import hashlib
import math
import secrets
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from pwdlib import PasswordHash
from pwdlib.exceptions import UnknownHashError

from app.config import settings

password_hash = PasswordHash.recommended()


def hash_password(plain_password: str) -> str:
    return password_hash.hash(plain_password)


def verify_password(plain_password: str, password_hash_value: str) -> bool:
    try:
        return password_hash.verify(plain_password, password_hash_value)
    except (UnknownHashError, ValueError):
        return False


def create_access_token(subject: str, expires_minutes: int | None = None) -> str:
    now = datetime.now(timezone.utc)
    lifetime = settings.jwt_expire_minutes if expires_minutes is None else expires_minutes
    return jwt.encode(
        {
            "sub": subject,
            "iat": now.timestamp(),
            "exp": (now + timedelta(minutes=lifetime)).timestamp(),
            "iss": "smartevent",
            "aud": "smartevent-api",
        },
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )


def new_refresh_token() -> tuple[str, str]:
    """A renewal key for the device, and the hash the database keeps instead of it."""
    token = secrets.token_urlsafe(48)
    return token, hash_refresh_token(token)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def decode_access_token(token: str) -> dict | None:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
            issuer="smartevent",
            audience="smartevent-api",
            options={"require_sub": True, "require_iat": True, "require_exp": True,
                     "require_iss": True, "require_aud": True},
        )
        issued_at, expires_at = payload["iat"], payload["exp"]
        if (any(type(value) not in (int, float) or not math.isfinite(value)
                for value in (issued_at, expires_at))
                or not 0 <= issued_at <= datetime.now(timezone.utc).timestamp()
                or issued_at >= expires_at):
            return None
        return payload
    except (JWTError, ValueError, TypeError, OverflowError):
        return None
