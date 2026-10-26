"""Bounded Excel parsing followed by atomic eligibility-roster insertion."""

from collections import defaultdict
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile

from fastapi import HTTPException
from openpyxl import load_workbook
from pydantic import ValidationError
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from app.models import CiteMember, Department, Organization
from app.schemas import CiteMemberCreate, RosterImportError
from app.services.access_audit import record_access_change

MAX_FILE_BYTES = 5 * 1024 * 1024
MAX_ROWS = 1000
HEADERS = ("Department", "Organization Full Name", "Full Name", "Email", "Role", "Position")
FIELD_COLUMNS = {"full_name": "Full Name", "email": "Email", "role": "Role", "position": "Position"}


def invalid(errors):
    raise HTTPException(422, {"code": "roster_import_invalid", "errors": [e.model_dump() for e in errors]})


def read_rows(content: bytes, filename: str):
    if Path(filename).suffix.lower() != ".xlsx" or not 0 < len(content) <= MAX_FILE_BYTES:
        raise HTTPException(400, "Upload an .xlsx workbook between 1 byte and 5 MiB")
    book = None
    try:
        # XLSX is a ZIP: bound expansion before the XML parser allocates memory.
        with ZipFile(BytesIO(content)) as archive:
            entries = archive.infolist()
            if len(entries) > 1000 or sum(e.file_size for e in entries) > 25 * 1024 * 1024:
                raise HTTPException(400, "Workbook expands beyond the supported size")
            if any("vbaproject" in e.filename.lower() for e in entries):
                raise HTTPException(400, "Macro-enabled workbooks are not supported")
        # Keep formulas visible so they cannot masquerade as cached roster values.
        book = load_workbook(BytesIO(content), read_only=True, data_only=False, keep_links=False)
        sheet = book.worksheets[0]
        sheet.reset_dimensions()
        rows = sheet.iter_rows(max_col=256)
        first = next(rows, ())
        columns = defaultdict(list)
        for index, cell in enumerate(first):
            if isinstance(cell.value, str):
                columns[cell.value.strip().casefold()].append(index)
        errors = []
        for header in HEADERS:
            matches = columns[header.casefold()]
            if len(matches) != 1:
                errors.append(RosterImportError(row=1, column=header, message="Required header is missing or duplicated"))
        if errors:
            invalid(errors)
        indices = [columns[h.casefold()][0] for h in HEADERS]
        parsed = []
        for number, cells in enumerate(rows, start=2):
            if number > 10001:
                raise HTTPException(400, "Workbook exceeds 10,000 worksheet rows; remove unused rows")
            values = [cells[i] for i in indices]
            if all(cell.value is None or (isinstance(cell.value, str) and not cell.value.strip()) for cell in values):
                continue
            if len(parsed) >= MAX_ROWS:
                raise HTTPException(400, "Workbook exceeds 1,000 data rows")
            row = {}
            for header, cell in zip(HEADERS, values):
                value = cell.value
                if cell.data_type in ("f", "e") or (value is not None and not isinstance(value, str)):
                    errors.append(RosterImportError(row=number, column=header, message="Use plain text, not formulas, errors, or numbers"))
                row[header] = value.strip() if isinstance(value, str) else ""
            parsed.append((number, row))
        if not parsed:
            errors.append(RosterImportError(row=2, column="Full Name", message="Workbook contains no roster members"))
        if errors:
            invalid(errors)
        return parsed
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(400, "Could not read the .xlsx workbook") from None
    finally:
        if book is not None:
            book.close()


def validate_roster_workbook(db, current_user, content: bytes, filename: str) -> list[CiteMemberCreate]:
    rows = read_rows(content, filename)
    departments = defaultdict(list)
    organizations = defaultdict(list)
    department_query = db.query(Department)
    organization_query = db.query(Organization)
    if current_user.role != "super_admin":
        department_query = department_query.filter(Department.id == current_user.department_id)
        organization_query = organization_query.filter(Organization.department_id == current_user.department_id)
    for department in department_query.all():
        departments[department.name.strip().casefold()].append(department)
    for organization in organization_query.all():
        organizations[(organization.department_id, organization.name.strip().casefold())].append(organization)

    errors, validated = [], []
    seen = {}
    email_rows = []
    for number, row in rows:
        def error(column, message):
            errors.append(RosterImportError(row=number, column=column, message=message))

        department_matches = departments[row["Department"].casefold()]
        department = department_matches[0] if len(department_matches) == 1 else None
        if department is None:
            error("Department", "Department name is missing, ambiguous, or outside your permitted scope")
        organization_matches = organizations[(department.id, row["Organization Full Name"].casefold())] if department else []
        organization = organization_matches[0] if len(organization_matches) == 1 else None
        if organization is None:
            error("Organization Full Name", "Organization must uniquely match an existing organization in the permitted department")
        try:
            member = CiteMemberCreate(
                full_name=row["Full Name"], email=row["Email"], role=row["Role"].lower(),
                position=row["Position"] or None,
                department_id=department.id if department else None,
                organization_id=organization.id if organization else None,
            )
        except ValidationError as exc:
            for issue in exc.errors():
                error(FIELD_COLUMNS.get(issue["loc"][0], str(issue["loc"][0])), issue["msg"])
            continue
        if member.email in seen:
            error("Email", f"Duplicate email in workbook (first appears on row {seen[member.email]})")
        else:
            seen[member.email] = number
        email_rows.append((number, member.email))
        validated.append(member)
    existing = set()
    emails = list(seen)
    # Chunk lookups for database parameter limits; do not reveal other organizations' records.
    for offset in range(0, len(emails), 400):
        existing.update(email.lower() for (email,) in db.query(CiteMember.email).filter(
            func.lower(CiteMember.email).in_(emails[offset:offset + 400])).all())
    for number, email in email_rows:
        if email in existing:
            errors.append(RosterImportError(row=number, column="Email", message="Email is already on the roster"))
    if errors:
        invalid(errors)
    return validated


def commit_roster_import(db, current_user, validated: list[CiteMemberCreate]) -> list[dict]:
    try:
        members = [CiteMember(**payload.model_dump()) for payload in validated]
        db.add_all(members)
        db.flush()
        for member in members:
            record_access_change(db, current_user, "roster.created", member)
        result = [{"id": member.id, "email": member.email} for member in members]
        db.commit()
        return result
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, {"code": "roster_import_conflict", "message": "Roster changed or conflicts with existing records; no rows imported"}) from None
    except SQLAlchemyError:
        db.rollback()
        raise
