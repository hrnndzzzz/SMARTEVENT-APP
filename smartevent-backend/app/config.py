"""
Central place for reading environment variables. Everything else in the
app imports `settings` from here instead of calling os.getenv() directly,
so there's exactly one place that knows about .env.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Supabase / Postgres
    database_url: str

    # Supabase Storage (used once receipt upload routes are built)
    supabase_url: str | None = None
    supabase_service_key: str | None = None
    supabase_receipts_bucket: str = "receipts"

    # JWT
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440  # 24 hours

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
