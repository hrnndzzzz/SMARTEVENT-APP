import pytest
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.compiler import compiles


@compiles(UUID, "sqlite")
def sqlite_uuid(type_, compiler, **kwargs):
    # SQLite's UUID affinity coerces numeric-looking hex into lossy numbers.
    return "CHAR(32)"


@pytest.fixture(autouse=True)
def no_receipt_cleanup_thread(monkeypatch):
    # Tests that configure storage must not start the daily cleanup against a real database.
    monkeypatch.setattr("app.services.receipt_retention.start_receipt_cleanup", lambda *args, **kwargs: None)


@pytest.fixture(autouse=True)
def reset_auth_request_limits():
    from app.main import app
    app.state.auth_rate_limits.clear()
