import argparse
import getpass
import sys
from pydantic import EmailStr, TypeAdapter, ValidationError
from sqlalchemy import func

from app.database import SessionLocal
from app.models import Department, User
from app.security import hash_password


DEPARTMENTS = [
    {
        "code": "SDS",
        "name": "Student Development Services",
        "description": "Oversees student organizations, activities, and development programs.",
    },
    {
        "code": "CITE",
        "name": "College of Information Technology Education",
        "description": "Primary department for the SMARTEVENT system.",
    },
]


def seed_departments(db) -> None:
    inserted = 0

    for data in DEPARTMENTS:
        existing = db.query(Department).filter(Department.code == data["code"]).first()
        if existing:
            print(f"  [skip] Department '{data['code']}' already exists.")
        else:
            db.add(Department(**data))
            inserted += 1
            print(f"  [add]  Department '{data['code']}' — {data['name']}")

    db.commit()
    print(f"\nDepartments: {inserted} inserted, {len(DEPARTMENTS) - inserted} already existed.\n")



def create_super_admin(db) -> None:
    existing_admin = db.query(User).filter(User.role == "super_admin").first()
    if existing_admin:
        print(f"A super_admin account already exists ({existing_admin.email}). Skipping.")
        return

    print("=== Create initial super_admin account ===")
    full_name = input("Full name: ").strip()
    email = input("Email: ").strip().lower()
    password = getpass.getpass("Password (min 8 chars): ")
    password_confirm = getpass.getpass("Confirm password: ")

    try:
        email = TypeAdapter(EmailStr).validate_python(email)
        if not 1 <= len(full_name) <= 150 or len(email) > 150:
            raise ValueError
    except (ValueError, ValidationError):
        print("ERROR: A valid name and email are required.")
        sys.exit(1)

    if not 8 <= len(password) <= 128:
        print("ERROR: Password must be between 8 and 128 characters.")
        sys.exit(1)

    if password != password_confirm:
        print("ERROR: Passwords do not match.")
        sys.exit(1)

    existing_email = db.query(User).filter(func.lower(User.email) == email).first()
    if existing_email:
        print(f"ERROR: A user with email '{email}' already exists.")
        sys.exit(1)

    user = User(
        full_name=full_name,
        email=email,
        password_hash=hash_password(password),
        role="super_admin",
        position="System Administrator",
        department_id=None,
        is_active=True,
        must_change_password=False,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    print(f"\n[ok] super_admin account created: {user.email} (id: {user.id})")
    print("     You can now log in via POST /auth/login with these credentials.\n")



def main() -> None:
    parser = argparse.ArgumentParser(description="Seed initial SMARTEVENT data.")
    parser.add_argument(
        "--create-admin",
        action="store_true",
        help="Also create the first super_admin account interactively.",
    )
    args = parser.parse_args()

    db = SessionLocal()
    try:
        print("\n--- Seeding departments ---")
        seed_departments(db)

        if args.create_admin:
            print("--- Creating super_admin ---")
            create_super_admin(db)
        else:
            print("Tip: run with --create-admin to also create the first super_admin account.\n")

    except KeyboardInterrupt:
        print("\nAborted.")
        db.rollback()
        sys.exit(1)
    finally:
        db.close()


if __name__ == "__main__":
    main()
