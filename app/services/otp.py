"""
Generates and verifies one-time codes. Reuses the same Argon2 hasher
already in app/security.py rather than a separate hashing scheme — an
OTP is just a short-lived secret, and hash/verify_password work on any
string, not just account passwords.
"""

import secrets

from app.security import hash_password, verify_password


def generate_otp_code() -> str:
    """A cryptographically random 6-digit code, e.g. '042817'."""
    return f"{secrets.randbelow(1_000_000):06d}"


def hash_otp_code(code: str) -> str:
    return hash_password(code)


def verify_otp_code(code: str, code_hash: str) -> bool:
    return verify_password(code, code_hash)
