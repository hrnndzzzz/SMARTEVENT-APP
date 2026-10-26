"""Excel imports must preserve roster scope and all-or-nothing semantics."""

from io import BytesIO

import pytest
from openpyxl import Workbook
from sqlalchemy import event
from sqlalchemy.exc import IntegrityError

from app.models import AuditLog, CiteMember, Department, Organization, User
from app.test_access_management import system  # noqa: F401


HEADERS = ["Department", "Organization Full Name", "Full Name", "Email", "Role", "Position"]


def workbook(rows, headers=HEADERS):
    book = Workbook()
    book.active.append(headers)
    for row in rows:
        book.active.append(row)
    output = BytesIO()
    book.save(output)
    book.close()
    return output.getvalue()


def member(email="new@example.com", **changes):
    data = dict(zip(HEADERS, ["CITE", "Organization A", "New Member", email, "Officer", None]))
    data.update(changes)
    return [data[key] for key in HEADERS]


def upload(client, rows=None, headers=HEADERS, content=None, filename="roster.xlsx"):
    return client.post("/cite-members/import", files={"file": (
        filename, content if content is not None else workbook(rows or [], headers),
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )})


def test_import_normalizes_and_audits_without_creating_accounts(system):
    client, db, users, orgs, _, login = system
    login("admin")
    before = db.query(User).count()
    response = upload(client, [member(" NEW@EXAMPLE.COM ", **{"Role": " TREASURER ", "Full Name": " New Member "}) + ["notes"]],
                      [" " + h.upper() + " " for h in HEADERS] + ["Notes"])
    assert response.status_code == 201, response.text
    assert response.json()["inserted_count"] == 1
    stored = db.query(CiteMember).filter_by(email="new@example.com").one()
    assert (stored.full_name, stored.role, stored.position, stored.organization_id) == ("New Member", "treasurer", None, orgs[0].id)
    assert stored.claimed_by_user_id is None
    assert db.query(User).count() == before
    assert db.query(AuditLog).filter_by(action="roster.created", entity_id=stored.id).count() == 1
    assert response.json()["members"] == [{"id": str(stored.id), "email": stored.email}]


@pytest.mark.parametrize("change,column", [
    ({"Full Name": ""}, "Full Name"), ({"Full Name": "x" * 151}, "Full Name"),
    ({"Email": "invalid"}, "Email"), ({"Role": "admin"}, "Role"),
    ({"Position": "x" * 51}, "Position"), ({"Department": "missing"}, "Department"),
    ({"Organization Full Name": "missing"}, "Organization Full Name"),
    ({"Full Name": "=1+1"}, "Full Name"),
])
def test_invalid_row_rolls_back_entire_file(system, change, column):
    client, db, _, _, _, login = system
    login("admin")
    response = upload(client, [member(), member("second@example.com", **change)])
    assert response.status_code == 422, response.text
    assert response.json()["detail"]["code"] == "roster_import_invalid"
    assert any(e["row"] == 3 and e["column"] == column for e in response.json()["detail"]["errors"])
    assert db.query(CiteMember).count() == 1
    assert db.query(AuditLog).count() == 0


@pytest.mark.parametrize("rows", [[member(), member("NEW@example.com")], [member(), member("OFFICER@example.com")]])
def test_duplicate_email_rejects_all_rows(system, rows):
    client, db, _, _, _, login = system
    login("admin")
    response = upload(client, rows)
    assert response.status_code == 422, response.text
    assert any(e["column"] == "Email" for e in response.json()["detail"]["errors"])
    assert db.query(CiteMember).count() == 1


@pytest.mark.parametrize("headers", [HEADERS[:-1], HEADERS + ["email"]])
def test_header_errors(system, headers):
    client, _, _, _, _, login = system
    login("admin")
    response = upload(client, [member()], headers)
    assert response.status_code == 422
    assert all(e["row"] == 1 for e in response.json()["detail"]["errors"])


@pytest.mark.parametrize("role", ["admin", "super_admin"])
def test_department_admin_and_super_admin_multi_organization(system, role):
    client, db, _, _, _, login = system
    rows = [member(), member("second@example.com", **{"Organization Full Name": "Organization B"})]
    login(role)
    response = upload(client, rows)
    assert response.status_code == 201, response.text
    assert response.json()["inserted_count"] == 2


@pytest.mark.parametrize("role", ["officer", "adviser", "treasurer", "sds_staff", "signatory"])
def test_non_admin_cannot_import(system, role):
    client, db, _, _, _, login = system
    login(role)
    assert upload(client, [member()]).status_code == 403
    assert db.query(CiteMember).count() == 1


@pytest.mark.parametrize("kind", ["department", "organization"])
def test_ambiguous_names_rejected(system, kind):
    client, db, users, _, _, login = system
    login("super_admin")
    duplicate = Department(code="OTHER", name=" cite ") if kind == "department" else Organization(
        code="OTHER", name=" organization a ", department_id=users["admin"].department_id)
    db.add(duplicate)
    db.commit()
    response = upload(client, [member()])
    assert response.status_code == 422, response.text
    assert db.query(CiteMember).count() == 1


@pytest.mark.parametrize("content,filename", [(b"bad", "roster.xlsx"), (b"bad", "roster.xls"),
                                                (b"x" * (5 * 1024 * 1024 + 1), "roster.xlsx")], ids=["corrupt", "xls", "oversized"])
def test_invalid_files(system, content, filename):
    client, db, _, _, _, login = system
    login("admin")
    assert upload(client, content=content, filename=filename).status_code == 400
    assert db.query(CiteMember).count() == 1


def test_row_limit_and_empty_file(system):
    client, _, _, _, _, login = system
    login("admin")
    assert upload(client, [member(f"n{i}@example.com") for i in range(1001)]).status_code == 400
    assert upload(client, []).status_code == 422


def test_blank_rows_preserve_excel_row_numbers(system):
    client, _, _, _, _, login = system
    login("admin")
    response = upload(client, [member(), [None] * 6, member("bad")])
    assert response.status_code == 422
    assert response.json()["detail"]["errors"][0]["row"] == 4


def test_database_conflict_rolls_back_rows_and_audits(system):
    client, db, _, _, _, login = system
    login("admin")
    def conflict(session, context, instances):
        if any(isinstance(obj, AuditLog) for obj in session.new):
            raise IntegrityError("insert", {}, Exception("simulated concurrent duplicate"))
    event.listen(db, "before_flush", conflict)
    try:
        response = upload(client, [member(), member("second@example.com")])
    finally:
        event.remove(db, "before_flush", conflict)
    assert response.status_code == 409, response.text
    assert db.query(CiteMember).count() == 1
    assert db.query(AuditLog).count() == 0
