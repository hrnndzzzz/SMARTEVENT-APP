import asyncio

import pytest
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError, ProgrammingError, SQLAlchemyError

from app.config import Settings
from app.main import app, database_error
from app.middleware import RequestSecurityMiddleware
from app.schemas import CategoryCreate, CategoryUpdate, CiteSelfRegisterRequest, EventUpdate, ReceiptParseRequest, VerifyOtpRequest


def test_production_settings_require_strong_secret_https_and_verified_database_tls():
    values = dict(_env_file=None, app_env="production", jwt_secret_key="a" * 32,
                  database_url="postgresql://app:private-password@db.example.edu/app?sslmode=verify-full",
                  allowed_origins="https://app.example.edu/")
    assert Settings(**values).cors_origins_list == ["https://app.example.edu"]
    for field, value in (("jwt_secret_key", "weak"), ("allowed_origins", "*"),
                         ("database_url", "postgresql://app:private-password@db.example.edu/app")):
        with pytest.raises(ValidationError) as error:
            Settings(**{**values, field: value})
        assert "private-password" not in str(error.value)
    assert "private-password" not in repr(Settings(**values))


def test_public_validation_errors_do_not_echo_passwords():
    with TestClient(app) as client:
        response = client.post("/auth/register", json={"email": "member@example.edu", "password": "S3cret"})
    assert response.status_code == 422
    assert "S3cret" not in response.text
    assert all("input" not in error and "ctx" not in error for error in response.json()["detail"])


@pytest.mark.parametrize("code", ["１２３４５６", "abcdef", "12345", "1234567"])
def test_registration_codes_require_six_ascii_digits(code):
    with pytest.raises(ValidationError):
        VerifyOtpRequest(email="member@example.edu", otp_code=code)


def test_account_and_financial_inputs_are_bounded():
    assert CiteSelfRegisterRequest(email="Member@example.edu", password="long-password").email == "member@example.edu"
    with pytest.raises(ValidationError):
        CiteSelfRegisterRequest(email="member@example.edu", password="x" * 129)
    for amount in ("NaN", "Infinity", "10000000000", "0.001"):
        with pytest.raises(ValidationError):
            CategoryCreate(name="Supplies", allocated_budget=amount)
    with pytest.raises(ValidationError):
        ReceiptParseRequest(raw_text="x" * 50001)


@pytest.mark.parametrize("schema,field", [(CategoryUpdate, "name"), (CategoryUpdate, "allocated_budget"),
                                         (EventUpdate, "title"), (EventUpdate, "allocated_budget")])
def test_patches_reject_clearing_required_fields(schema, field):
    with pytest.raises(ValidationError):
        schema(**{field: None})


def test_auth_request_limits_ignore_untrusted_forwarding_headers():
    limited_app = FastAPI(root_path="/api")
    limited_app.add_middleware(RequestSecurityMiddleware, max_auth_requests=2)

    @limited_app.post("/auth/login")
    def login():
        return {"ok": True}

    with TestClient(limited_app) as client:
        assert client.post("/api/auth/login").status_code == 200
        assert client.post("/api/auth/login", headers={"X-Forwarded-For": "different-address"}).status_code == 200
        response = client.post("/api/auth/login")
    assert response.status_code == 429
    assert int(response.headers["Retry-After"]) > 0
    assert response.headers["Cache-Control"] == "no-store"


def test_request_limit_applies_before_parsing_even_without_content_length():
    calls, sent = [], []
    messages = iter([{"type": "http.request", "body": b"123", "more_body": True},
                     {"type": "http.request", "body": b"456", "more_body": False}])

    async def downstream(scope, receive, send):
        calls.append(True)

    async def receive():
        return next(messages)

    async def send(message):
        sent.append(message)

    scope = {"type": "http", "method": "POST", "path": "/upload", "headers": []}
    asyncio.run(RequestSecurityMiddleware(downstream, max_body_bytes=5)(scope, receive, send))
    assert calls == []
    assert sent[0]["status"] == 413


def test_bounded_requests_replay_body_and_keep_one_security_header():
    limited_app = FastAPI()
    limited_app.add_middleware(RequestSecurityMiddleware, max_body_bytes=5)

    @limited_app.post("/echo")
    async def echo(request: Request):
        return {"body": (await request.body()).decode()}

    with TestClient(limited_app) as client:
        assert client.post("/echo", content=b"12345").json() == {"body": "12345"}
        response = client.post("/echo", content=b"123456")
    assert response.status_code == 413
    assert response.headers["Cache-Control"] == "no-store"
    assert response.headers["X-Content-Type-Options"] == "nosniff"


@pytest.mark.parametrize("error,expected", [
    (SQLAlchemyError("private-database-credentials"), 503),
    (IntegrityError("private-query", {"password": "private-password"}, Exception("private-error")), 409),
])
def test_database_errors_do_not_disclose_queries_or_credentials(error, expected, caplog):
    failing_app = FastAPI()
    failing_app.add_exception_handler(SQLAlchemyError, database_error)

    @failing_app.get("/")
    def fail():
        raise error

    with TestClient(failing_app) as client:
        response = client.get("/")
    assert response.status_code == expected
    assert "private" not in response.text
    assert "private" not in caplog.text
    if expected == 409:
        assert not [record for record in caplog.records if record.name == "app.main"]
    else:
        assert "SQLAlchemyError (SQLSTATE unknown)" in caplog.text


@pytest.mark.parametrize("sqlstate", ["42703", "42P01"])
def test_missing_schema_logging_is_actionable_without_disclosing_database_data(sqlstate, caplog):
    class DatabaseFailure(Exception):
        pgcode = sqlstate

    error = ProgrammingError("private-query", {"password": "private-password"}, DatabaseFailure("private-error"))
    failing_app = FastAPI()
    failing_app.add_exception_handler(SQLAlchemyError, database_error)

    @failing_app.get("/{private_identifier}")
    def fail(private_identifier: str):
        raise error

    with TestClient(failing_app) as client:
        response = client.get("/private-user-id?code=private-otp")
    assert response.status_code == 503
    assert response.json() == {"detail": "The database is temporarily unavailable"}
    assert f"ProgrammingError (SQLSTATE {sqlstate})" in caplog.text
    assert "Apply pending database migrations." in caplog.text
    assert "private" not in response.text and "private" not in caplog.text
    assert all(record.exc_info is None for record in caplog.records if record.name == "app.main")
