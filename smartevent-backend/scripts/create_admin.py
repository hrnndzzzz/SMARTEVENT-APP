"""Create an Admin account with python -m scripts.create_admin."""

import sys
from pydantic import ValidationError
from sqlalchemy import func

from app.database import SessionLocal
from app.models import Department, Organization, User
from app.schemas import AdminRegisterRequest
from app.services.account_provisioning import create_user_with_temp_password
from app.services.email import EmailError


def main() -> None:
    full_name = input("Full name: ").strip()
    email = input("Email: ").strip().lower()
    department_id_value = input("Department ID: ").strip()
    organization_id_value = input("Organization ID: ").strip()
    position = input("Position (optional): ").strip() or None

    try:
        payload = AdminRegisterRequest(
            full_name=full_name, email=email, position=position,
            department_id=department_id_value, organization_id=organization_id_value,
        )
    except ValidationError:
        print("Provide a valid name, email, department ID, organization ID, and position.", file=sys.stderr)
        sys.exit(1)

    db = SessionLocal()
    try:
        existing = db.query(User).filter(func.lower(User.email) == payload.email).first()
        if existing:
            print(f"A user with email '{email}' already exists.", file=sys.stderr)
            sys.exit(1)

        department = db.query(Department).filter(Department.id == payload.department_id).first()
        if department is None:
            print("No department exists with that ID.", file=sys.stderr)
            sys.exit(1)

        organization = db.query(Organization).filter(Organization.id == payload.organization_id).first()
        if organization is None or organization.department_id != department.id:
            print("Choose an organization in the selected department.", file=sys.stderr)
            sys.exit(1)

        user = create_user_with_temp_password(
            db,
            full_name=payload.full_name,
            email=payload.email,
            role="admin",
            position=payload.position,
            department_id=department.id,
            organization_id=organization.id,
        )
        db.commit()
        print(f"\nAdmin account created: {user.email}")
        print("A temporary password has been emailed to them.")
        print("They must log in and change it via POST /auth/change-password.\n")

    except (RuntimeError, EmailError) as exc:
        db.rollback()
        print(f"\nFailed to create account: {exc}", file=sys.stderr)
        print(
            "Check RESEND_API_KEY / RESEND_FROM_EMAIL in .env are set "
            "correctly and the sender domain is verified, then try again.",
            file=sys.stderr,
        )
        sys.exit(1)
    finally:
        db.close()


if __name__ == "__main__":
    main()
