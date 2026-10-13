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

    # Gemini (used by app/services/ocr.py to parse OCR text extracted
    # on-device by the Flutter app into structured merchant/date/amount)
    gemini_api_key: str | None = None
    gemini_model: str = "gemini-3.5-flash-lite"

    # JWT
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 1440  # 24 hours

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
