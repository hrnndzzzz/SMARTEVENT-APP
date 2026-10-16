"""Regression tests for fail-closed department authorization."""

from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.dependencies import assert_department_scope, resolve_department_id


def make_user(role: str, department_id):
    return SimpleNamespace(
        role=role,
        department_id=department_id,
        must_change_password=False,
    )


def test_scoped_reader_cannot_access_unscoped_record():
    user = make_user("officer", uuid4())

    with pytest.raises(HTTPException) as exc_info:
        assert_department_scope(user, None, allow_officer_read=True)

    assert exc_info.value.status_code == 403


def test_scoped_reader_can_access_record_in_own_department():
    department_id = uuid4()
    user = make_user("officer", department_id)

    assert_department_scope(user, department_id, allow_officer_read=True) is None


def test_scoped_writer_department_is_derived_from_account():
    department_id = uuid4()
    user = make_user("treasurer", department_id)

    assert resolve_department_id(user, None) == department_id


def test_scoped_writer_cannot_select_another_department():
    user = make_user("adviser", uuid4())

    with pytest.raises(HTTPException) as exc_info:
        resolve_department_id(user, uuid4())

    assert exc_info.value.status_code == 403


def test_admin_can_access_only_its_assigned_department():
    department_id = uuid4()
    admin = make_user("admin", department_id)

    assert_department_scope(admin, department_id)

    with pytest.raises(HTTPException) as exc_info:
        assert_department_scope(admin, uuid4())

    assert exc_info.value.status_code == 403


def test_admin_cannot_access_department_scope_without_assignment():
    admin = make_user("admin", None)

    with pytest.raises(HTTPException) as exc_info:
        assert_department_scope(admin, uuid4())

    assert exc_info.value.status_code == 403


def test_admin_record_creation_defaults_to_its_department():
    department_id = uuid4()
    admin = make_user("admin", department_id)

    assert resolve_department_id(admin, None, require_for_admin=True) == department_id


def test_super_admin_can_select_any_department():
    requested_department_id = uuid4()
    super_admin = make_user("super_admin", None)

    assert resolve_department_id(
        super_admin,
        requested_department_id,
        require_for_admin=True,
    ) == requested_department_id
