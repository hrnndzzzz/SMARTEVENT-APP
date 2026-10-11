"""
Central place for reading environment variables. Everything else in the
app imports `settings` from here instead of calling os.getenv() directly,
so there's exactly one place that knows about .env.

If a REQUIRED variable (database_url, jwt_secret_key) is missing, this
module fails immediately and loudly at import time — before uvicorn
even finishes starting — rather than letting the app come up and fail
confusingly on the first request that happens to touch the missing
value. See the try/except around Settings() at the bottom.
"""

import sys

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Supabase / Postgres — REQUIRED
    database_url: str

    # CORS — comma-separated list of allowed origins in .env, e.g.
    #   ALLOWED_ORIGINS=https://smartevent.app,https://staging.smartevent.app
    # Defaults to "*" (allow everything) so local development keeps
    # working out of the box without needing to set this. Tighten it
    # to real origins before deploying anywhere public.
    allowed_origins: str = "*"

    # Supabase Storage — optional. Receipt upload/scan-receipt return a
    # clean 503 ("Supabase Storage is not configured") if these are
    # missing, rather than crashing — see app/services/storage.py.
    supabase_url: str | None = None
    supabase_service_key: str | None = None
    supabase_receipts_bucket: str = "receipts"

    # Gemini — optional. parse-receipt/scan-receipt return a clean 503
    # if this is missing — see app/services/ocr.py.
    gemini_api_key: str | None = None
    gemini_model: str = "gemini-3.5-flash-lite"

    # Resend — used for registration, initial setup, and password-reset OTP emails.
    resend_api_key: str | None = None
    resend_from_email: str | None = None
    resend_test_email: str | None = None

    # Accepted for backward compatibility with existing .env files; never used.
    gmail_address: str | None = None
    gmail_app_password: str | None = None
    gmail_from_name: str | None = None

    # How long an OTP (temp password OR password-reset code) stays
    # valid, in minutes, before the user has to request a new one.
    otp_expiry_minutes: int = 15

    # Supabase Storage bucket for uploaded proposal letter documents,
    # separate from supabase_receipts_bucket above.
    supabase_proposal_letters_bucket: str = "proposal-letters"

    # JWT — REQUIRED (jwt_secret_key)
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440  # 24 hours

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    @field_validator("allowed_origins")
    @classmethod
    def _strip_trailing_slashes(cls, value: str) -> str:
        # A trailing slash on an origin (https://example.com/ instead of
        # https://example.com) silently breaks CORS matching — the
        # browser sends an Origin header with no trailing slash, so a
        # configured origin with one never matches. Strip defensively
        # rather than let that be a confusing "CORS just doesn't work"
        # bug someone hits weeks from now.
        return ",".join(origin.strip().rstrip("/") for origin in value.split(","))

    @property
    def cors_origins_list(self) -> list[str]:
        """
        What actually gets passed to CORSMiddleware's allow_origins.
        "*" stays a single-item list (FastAPI/Starlette's own wildcard
        handling); anything else is split on commas into real origins.
        """
        if self.allowed_origins.strip() == "*":
            return ["*"]
        return [origin for origin in self.allowed_origins.split(",") if origin]


def _load_settings() -> Settings:
    try:
        return Settings()
    except Exception as exc:
        # pydantic-settings' own ValidationError is technically
        # complete but easy to misread at a glance (a wall of nested
        # "field required" errors). This reformats it into something
        # that says exactly what to do, and fails BEFORE uvicorn
        # reports "Application startup complete" — so a missing .env
        # value is caught at the earliest possible moment, not on the
        # first request that happens to need it.
        print("\n" + "=" * 70, file=sys.stderr)
        print("STARTUP FAILED: required environment variables are missing", file=sys.stderr)
        print("=" * 70, file=sys.stderr)
        print(f"\n{exc}\n", file=sys.stderr)
        print(
            "Check your .env file exists in the project root and defines "
            "at least DATABASE_URL and JWT_SECRET_KEY. See .env.example "
            "for the full list of variables this app reads.",
            file=sys.stderr,
        )
        print("=" * 70 + "\n", file=sys.stderr)
        sys.exit(1)


settings = _load_settings()

# Informational only — these features degrade gracefully with a clean
# 503 at request time if unconfigured (see ocr.py / storage.py), so
# missing them is NOT fatal. But it's worth knowing at a glance from
# the startup log rather than discovering it only when a request fails.
if not settings.gemini_api_key:
    print(
        "[startup] NOTE: GEMINI_API_KEY not set — "
        "parse-receipt and scan-receipt will return 503 until it is.",
        file=sys.stderr,
    )
if not settings.supabase_url or not settings.supabase_service_key:
    print(
        "[startup] NOTE: SUPABASE_URL / SUPABASE_SERVICE_KEY not set — "
        "receipt image upload will return 503 until both are.",
        file=sys.stderr,
    )
if not settings.resend_api_key or not settings.resend_from_email:
    print(
        "[startup] NOTE: RESEND_API_KEY / RESEND_FROM_EMAIL not set — "
        "account creation and password reset will return 503 until "
        "both are configured (OTP email delivery is unavailable).",
        file=sys.stderr,
    )
