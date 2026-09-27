"""
Manual Admin account creation CLI script — run this directly, NOT through
the API. Useful for IT staff or initializing admin accounts.

Usage (from project root, with venv active and .env present):

    python -m scripts.create_admin
"""

import sys
import uuid

from app.database import SessionLocal
from app.models import Department, Organization, User
from app.services.account_provisioning import create_user_with_temp_password
from app.services.email import EmailError


def main() -> None:
    full_name = input("Full name: ").strip()
    email = input("Email: ").strip()
    department_id_value = input("Department ID: ").strip()
    organization_id_value = input("Organization ID: ").strip()
    position = input("Position (optional): ").strip() or None

    try:
        department_id = uuid.UUID(department_id_value)
        organization_id = uuid.UUID(organization_id_value)
    except ValueError:
        print("A valid department ID is required.", file=sys.stderr)
        sys.exit(1)

    if not full_name or not email:
        print("Full name and email are both required.", file=sys.stderr)
        sys.exit(1)

    db = SessionLocal()
    try:
        existing = db.query(User).filter(User.email == email).first()
        if existing:
            print(f"A user with email '{email}' already exists.", file=sys.stderr)
            sys.exit(1)

        department = db.query(Department).filter(Department.id == department_id).first()
        if department is None:
            print("No department exists with that ID.", file=sys.stderr)
            sys.exit(1)

        organization = db.query(Organization).filter(Organization.id == organization_id).first()
        if organization is None or organization.department_id != department.id:
            print("Choose an organization in the selected department.", file=sys.stderr)
            sys.exit(1)

        user = create_user_with_temp_password(
            db,
            full_name=full_name,
            email=email,
            role="admin",
            position=position,
            department_id=department.id,
            organization_id=organization.id,
        )
        user.department_id = department.id
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
