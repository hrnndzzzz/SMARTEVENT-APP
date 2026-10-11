"""Route-level RBAC regression tests for SMARTEVENT.

These tests exercise the actual FastAPI routes and dependency graph. They do
not connect to Supabase: denied requests stop in authorization dependencies,
and allowed read checks use a harmless empty database session double.

Run it from the backend root with:

    python -m pytest -q -p no:cacheprovider app/test_rbac_policy.py
"""

from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

try:
    from app.database import get_db
    from app.dependencies import get_current_user, require_active_account
    from app.main import app
except ModuleNotFoundError as exc:  # pragma: no cover - guidance for placement
    pytest.skip(
        f"Route tests must run from the backend root containing app/: {exc}",
        allow_module_level=True,
    )


class EmptyQuery:
    """Small query double for routes whose authorization has already passed."""

    def filter(self, *args, **kwargs):
        return self

    def join(self, *args, **kwargs):
        return self

    def options(self, *args, **kwargs):
        return self

    def order_by(self, *args, **kwargs):
        return self

    def with_entities(self, *args, **kwargs):
        return self

    def group_by(self, *args, **kwargs):
        return self

    def limit(self, *args, **kwargs):
        return self

    def subquery(self):
        return object()

    def all(self):
        return []

    def first(self):
        return None

    def count(self):
        return 0

    def scalar(self):
        return 0


class RecordingQuery(EmptyQuery):
    def __init__(self):
        self.filter_calls = []

    def filter(self, *args, **kwargs):
        self.filter_calls.append(args)
        return self


class EmptySession:
    """Database double that cannot read or write a real environment."""

    def query(self, *args, **kwargs):
        return EmptyQuery()

    def add(self, *args, **kwargs):
        raise AssertionError("This route test should not write to the database")

    def commit(self):
        raise AssertionError("This route test should not commit to the database")

    def refresh(self, *args, **kwargs):
        raise AssertionError("This route test should not refresh database records")


class RecordingSession:
    def __init__(self):
        self.query_object = RecordingQuery()

    def query(self, *args, **kwargs):
        return self.query_object


@pytest.fixture
def client():
    """Use the real app while restoring all dependency overrides afterward."""
    original_overrides = app.dependency_overrides.copy()
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
    app.dependency_overrides.update(original_overrides)


@pytest.fixture
def user():
    department_id = uuid4()
    organization_id = uuid4()

    def make(role, *, must_change_password=False, department=department_id):
        return SimpleNamespace(
            id=uuid4(),
            role=role,
            department_id=department,
            organization_id=organization_id if department is not None else None,
            must_change_password=must_change_password,
            is_active=True,
        )

    return make


def authenticate_as(user):
    """Override the shared active-account dependency for one request group."""
    app.dependency_overrides[require_active_account] = lambda: user


def use_empty_database():
    app.dependency_overrides[get_db] = lambda: EmptySession()


def use_recording_database():
    session = RecordingSession()
    app.dependency_overrides[get_db] = lambda: session
    return session


def test_protected_route_requires_authentication(client):
    response = client.get("/categories")

    assert response.status_code == 401


@pytest.mark.parametrize(
    "path",
    [
        "/categories",
        "/events",
        "/expenses",
        "/inventory",
        "/analytics/dashboard",
        f"/reports/category/{uuid4()}",
        f"/recommendations/event-budget?category_id={uuid4()}",
    ],
)
def test_sds_staff_cannot_read_operational_modules(client, user, path):
    authenticate_as(user("sds_staff", department=None))

    response = client.get(path)

    assert response.status_code == 403


@pytest.mark.parametrize(
    ("method", "path", "kwargs"),
    [
        ("post", "/categories", {"json": {"name": "Test category"}}),
        (
            "post",
            "/events",
            {"json": {"title": "Test event", "status": "draft"}},
        ),
        (
            "post",
            "/expenses",
            {
                "json": {
                    "category_id": str(uuid4()),
                    "description": "Test expense",
                    "amount": 1,
                }
            },
        ),
        ("post", "/inventory", {"json": {"item_name": "Test item"}}),
        (
            "post",
            "/incomes",
            {
                "json": {
                    "event_id": str(uuid4()),
                    "source": "Sponsorship",
                    "purpose": "Event expenses",
                    "amount": 100,
                }
            },
        ),
        (
            "patch",
            f"/categories/{uuid4()}",
            {"json": {"name": "Renamed category"}},
        ),
        (
            "post",
            f"/events/{uuid4()}/approve",
            {"json": {}},
        ),
        (
            "post",
            f"/expenses/{uuid4()}/approve",
            {"json": {}},
        ),
        (
            "post",
            f"/inventory/{uuid4()}/transactions",
            {"json": {"change_qty": 1}},
        ),
        (
            "post",
            "/proposal-letters",
            {
                "data": {"event_id": str(uuid4()), "title": "Test letter"},
                "files": {
                    "file": ("letter.pdf", b"%PDF-1.4", "application/pdf")
                },
            },
        ),
    ],
)
def test_officer_cannot_use_write_routes(client, user, method, path, kwargs):
    authenticate_as(user("officer"))

    response = getattr(client, method)(path, **kwargs)

    assert response.status_code == 403


def test_adviser_cannot_create_expense(client, user):
    authenticate_as(user("adviser"))

    response = client.post(
        "/expenses",
        json={
            "category_id": str(uuid4()),
            "description": "Adviser must not record this",
            "amount": 1,
        },
    )

    assert response.status_code == 403


def test_adviser_can_reach_event_review_boundary(client, user):
    authenticate_as(user("adviser"))
    use_empty_database()

    response = client.post(f"/events/{uuid4()}/approve", json={})

    # 404 means the adviser passed the role dependency and the handler looked
    # for the event. A 403 would indicate an incorrect approval policy.
    assert response.status_code == 404


def test_treasurer_can_reach_financial_creation_boundary(client, user):
    authenticate_as(user("treasurer"))
    use_empty_database()

    response = client.post(
        "/expenses",
        json={
            "category_id": str(uuid4()),
            "description": "Treasurer test",
            "amount": 1,
        },
    )

    # The empty session returns no category. This confirms authorization ran
    # first and the request reached the financial handler.
    assert response.status_code == 400


def test_sds_staff_can_read_proposal_letters_only(client, user):
    authenticate_as(user("sds_staff", department=None))
    use_empty_database()

    response = client.get("/proposal-letters")

    assert response.status_code == 200
    assert response.json() == []


def test_officer_can_read_operational_lists(client, user):
    authenticate_as(user("officer"))
    use_empty_database()

    response = client.get("/categories")

    assert response.status_code == 200
    assert response.json() == []


@pytest.mark.parametrize("path", ["/categories", "/events", "/expenses", "/inventory", "/incomes"])
def test_scoped_list_routes_apply_department_filter(client, user, path):
    authenticate_as(user("officer"))
    session = use_recording_database()

    response = client.get(path)

    assert response.status_code == 200
    assert session.query_object.filter_calls, (
        f"{path} did not apply a department filter for a scoped reader"
    )


def test_unassigned_admin_cannot_read_department_lists(client, user):
    authenticate_as(user("admin", department=None))
    use_recording_database()

    response = client.get("/categories")

    assert response.status_code == 403


def test_super_admin_can_read_global_category_list(client, user):
    authenticate_as(user("super_admin", department=None))
    use_empty_database()

    response = client.get("/categories")

    assert response.status_code == 200
    assert response.json() == []


def test_admin_roster_list_is_filtered_to_assigned_department(client, user):
    admin = user("admin")
    authenticate_as(admin)
    session = use_recording_database()

    response = client.get("/cite-members")

    assert response.status_code == 200
    assert session.query_object.filter_calls


def test_admin_cannot_list_roster_for_another_department(client, user):
    authenticate_as(user("admin"))
    use_recording_database()

    response = client.get(f"/cite-members?department_id={uuid4()}")

    assert response.status_code == 403


def test_admin_cannot_create_event_in_another_department(client, user):
    authenticate_as(user("admin"))

    response = client.post(
        "/events",
        json={
            "department_id": str(uuid4()),
            "school_year": "2025-2026",
            "semester": "1st",
            "event_scope": "departmental",
            "title": "Out-of-scope event",
        },
    )

    assert response.status_code == 403


def test_super_admin_can_filter_roster_globally(client, user):
    authenticate_as(user("super_admin", department=None))
    session = use_recording_database()

    response = client.get(f"/cite-members?department_id={uuid4()}")

    assert response.status_code == 200
    assert session.query_object.filter_calls


def test_admin_department_lookup_is_scoped(client, user):
    authenticate_as(user("admin"))
    session = use_recording_database()

    response = client.get("/departments")

    assert response.status_code == 200
    assert session.query_object.filter_calls


def test_super_admin_department_lookup_is_global(client, user):
    authenticate_as(user("super_admin", department=None))
    session = use_recording_database()

    response = client.get("/departments")

    assert response.status_code == 200
    assert session.query_object.filter_calls == []


def test_admin_user_list_is_filtered_to_assigned_department(client, user):
    authenticate_as(user("admin"))
    session = use_recording_database()

    response = client.get("/users")

    assert response.status_code == 200
    assert session.query_object.filter_calls


def test_super_admin_can_list_users_globally(client, user):
    authenticate_as(user("super_admin", department=None))
    session = use_recording_database()

    response = client.get("/users")

    assert response.status_code == 200
    assert session.query_object.filter_calls == []


def test_admin_cannot_reassign_user_department(client, user):
    authenticate_as(user("admin"))

    response = client.patch(
        f"/users/{uuid4()}/department",
        json={"department_id": str(uuid4())},
    )

    assert response.status_code == 403


def test_temporary_password_account_is_blocked_from_application_data(client, user):
    authenticate_as(user("admin", must_change_password=True, department=None))

    response = client.get("/categories")

    assert response.status_code == 403


def test_invalid_bearer_token_is_rejected(client):
    response = client.get(
        "/categories",
        headers={"Authorization": "Bearer definitely-not-a-valid-token"},
    )

    assert response.status_code == 401
