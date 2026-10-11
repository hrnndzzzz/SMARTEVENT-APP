"""
Password hashing (Argon2) and JWT creation/verification
(via python-jose).

Nothing in here talks to the database — it's pure
crypto/token logic, used by routers/auth.py and dependencies.py.
"""

from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from pwdlib import PasswordHash

from app.config import settings


# Password hashing
# Argon2 is used instead of Passlib/bcrypt.
password_hash = PasswordHash.recommended()


def hash_password(plain_password: str) -> str:
    """
    Hash a plain-text password using Argon2.
    """
    return password_hash.hash(plain_password)


def verify_password(
    plain_password: str,
    password_hash_value: str,
) -> bool:
    """
    Verify a plain-text password against a previously generated hash.
    """
    return password_hash.verify(
        plain_password,
        password_hash_value,
    )


# JWT
def create_access_token(
    subject: str,
    expires_minutes: int | None = None,
) -> str:
    """
    Create a JWT access token.

    `subject` is the user's ID as a string.
    It is stored in the JWT `sub` claim and read back by
    dependencies.py.
    """

    expire = datetime.now(timezone.utc) + timedelta(
        minutes=expires_minutes or settings.jwt_expire_minutes
    )

    to_encode = {
        "sub": subject,
        "exp": expire,
    }

    return jwt.encode(
        to_encode,
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )


def decode_access_token(token: str) -> str | None:
    """
    Decode and validate a JWT access token.

    Returns the user ID from the `sub` claim if the token
    is valid. Returns None if the token is invalid or expired.
    """

    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
        )

        return payload.get("sub")

    except JWTError:
        return None