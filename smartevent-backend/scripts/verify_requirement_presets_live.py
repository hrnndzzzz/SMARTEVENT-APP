"""Read-only live-DB smoke test: python -m scripts.verify_requirement_presets_live.

Uses the local FastAPI app and configured database, not a deployed HTTP server.
Issues one-minute diagnostic tokens for existing ready accounts, never prints
tokens or account identifiers, and never changes passwords or creates users.
"""

import json

from fastapi.testclient import TestClient
from sqlalchemy import and_, event, or_, text
from sqlalchemy.exc import SQLAlchemyError

from app.database import SessionLocal, engine
from app.main import app
from app.models import User
from app.security import create_access_token


def verify():
    def read_only(connection):
        connection.exec_driver_sql("SET TRANSACTION READ ONLY")
        connection.exec_driver_sql("SET LOCAL statement_timeout = '15s'")

    event.listen(engine, "begin", read_only)
    try:
        allowed = {"super_admin", "admin", "adviser", "treasurer", "officer"}
        expected_codes = {"parent_guardian_consent", "medical_clearance", "student_learning_journal"}
        with SessionLocal() as db:
            assert db.execute(text("SHOW transaction_read_only")).scalar_one() == "on"
            accounts = db.query(User.id, User.role).filter(
                User.is_active.is_(True), User.is_suspended.is_(False),
                User.must_change_password.is_(False),
                or_(User.role.in_(["super_admin", "sds_staff", "signatory"]),
                    and_(User.organization_id.is_not(None), User.department_id.is_not(None))),
            ).order_by(User.id).all()
        by_role = {}
        for user_id, role in accounts:
            by_role.setdefault(role, user_id)
        assert allowed.intersection(by_role), "No ready operational account is available for verification"

        path = "/events/requirement-presets"
        results = {}
        with TestClient(app) as client:
            assert client.get(path).status_code == 401
            results["unauthenticated"] = 401
            for role, user_id in by_role.items():
                token = create_access_token(str(user_id), expires_minutes=1)
                response = client.get(path, headers={"Authorization": "Bearer " + token})
                expected_status = 200 if role in allowed else 403
                assert response.status_code == expected_status, f"{role}: expected {expected_status}, received {response.status_code}"
                if expected_status == 200:
                    presets = response.json()
                    assert len(presets) == 3
                    assert {preset["code"] for preset in presets} == expected_codes
                    assert all("id" in preset and "phase" in preset for preset in presets)
                    assert response.headers["cache-control"] == "no-store"
                results[role] = response.status_code
        print(json.dumps({"endpoint": path, "transport": "local ASGI app / live PostgreSQL",
                          "http_status_by_role": results, "preset_codes": sorted(expected_codes),
                          "database_transactions": "read-only"}, indent=2))
    finally:
        event.remove(engine, "begin", read_only)
        engine.dispose()


if __name__ == "__main__":
    try:
        verify()
    except SQLAlchemyError as exc:
        original = getattr(exc, "orig", None)
        code = getattr(original, "pgcode", None) or "unknown"
        raise SystemExit(f"Database verification failed: {type(exc).__name__}, SQLSTATE {code}") from None
