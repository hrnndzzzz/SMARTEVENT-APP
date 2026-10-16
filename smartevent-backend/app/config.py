from typing import Literal
from urllib.parse import urlsplit

from pydantic import Field, ValidationError, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url


class Settings(BaseSettings):
    app_env: Literal["development", "production"] = "development"
    database_url: str = Field(min_length=1, repr=False)
    allowed_origins: str = "http://localhost:3000,http://127.0.0.1:3000"
    supabase_url: str | None = None
    supabase_service_key: str | None = Field(default=None, repr=False)
    supabase_receipts_bucket: str = "receipts"
    supabase_proposal_letters_bucket: str = "proposal-letters"
    gemini_api_key: str | None = Field(default=None, repr=False)
    gemini_model: str = "gemini-3.5-flash-lite"
    resend_api_key: str | None = Field(default=None, repr=False)
    resend_from_email: str | None = None
    resend_test_email: str | None = None
    otp_expiry_minutes: int = Field(default=15, ge=1, le=30)
    jwt_secret_key: str = Field(min_length=1, repr=False)
    jwt_algorithm: Literal["HS256"] = "HS256"
    jwt_expire_minutes: int = Field(default=60, ge=1, le=1440)

    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore", hide_input_in_errors=True,
    )

    @field_validator("allowed_origins")
    @classmethod
    def normalize_origins(cls, value: str) -> str:
        origins = [origin.strip().rstrip("/") for origin in value.split(",") if origin.strip()]
        for origin in origins:
            parsed = urlsplit(origin)
            if origin != "*" and (parsed.scheme not in {"http", "https"} or not parsed.netloc
                                  or parsed.path or parsed.query or parsed.fragment or parsed.username):
                raise ValueError("Origins must be HTTP(S) origins without paths or credentials")
        if "*" in origins and len(origins) != 1:
            raise ValueError("Wildcard origins cannot be combined with explicit origins")
        return ",".join(dict.fromkeys(origins))

    @model_validator(mode="after")
    def production_security(self):
        if self.app_env == "production":
            if len(self.jwt_secret_key.encode()) < 32:
                raise ValueError("Production JWT signing secrets require at least 32 bytes")
            if not self.cors_origins_list or any(not origin.startswith("https://") for origin in self.cors_origins_list):
                raise ValueError("Production requires explicit HTTPS frontend origins")
            database = make_url(self.database_url)
            if database.get_backend_name() != "postgresql" or database.query.get("sslmode") != "verify-full":
                raise ValueError("Production PostgreSQL connections require sslmode=verify-full")
            if self.supabase_url and not self.supabase_url.startswith("https://"):
                raise ValueError("Production Supabase connections require HTTPS")
        return self

    @property
    def cors_origins_list(self) -> list[str]:
        return self.allowed_origins.split(",") if self.allowed_origins else []


try:
    settings = Settings()
except ValidationError as exc:
    fields = ", ".join(sorted({".".join(map(str, error["loc"])) or "production security" for error in exc.errors()}))
    raise RuntimeError(f"Invalid settings: {fields}. Check the environment and .env.example.") from None
