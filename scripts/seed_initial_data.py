"""
One-time seed script — run directly on the server (or locally against
the real DB) to:

  1. Insert the initial department rows (SDS, CBA, CEA, SCS, CITE).
  2. Optionally create the first super_admin account if one doesn't
     exist yet.

Run with:
    python -m scripts.seed_initial_data

Or with explicit super_admin creation:
    python -m scripts.seed_initial_data --create-admin

Requires DATABASE_URL (and JWT_SECRET_KEY) in .env, same as the app.
Does NOT go through the HTTP API — talks to the DB directly via
SQLAlchemy, same pattern as scripts/create_super_admin.py.

Safe to re-run: departments are inserted with ON CONFLICT DO NOTHING
logic (checks by code before inserting), so running it twice won't
create duplicates or overwrite anything.
"""

import argparse
import getpass
import sys
from pathlib import Path

# Allow running as `python -m scripts.seed_initial_data` from the project root.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database import SessionLocal
from app.models import Department, User
from app.security import hash_password

# ---------------------------------------------------------------------------
# Department seed data
# ---------------------------------------------------------------------------

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


def seed_departments(db) -> dict[str, Department]:
    """
    Inserts any department from DEPARTMENTS that doesn't already exist
    (matched by code). Returns a dict of code -> Department for use by
    the admin-creation step.
    """
    inserted = 0
    dept_map: dict[str, Department] = {}

    for data in DEPARTMENTS:
        existing = db.query(Department).filter(Department.code == data["code"]).first()
        if existing:
            print(f"  [skip] Department '{data['code']}' already exists.")
            dept_map[data["code"]] = existing
        else:
            dept = Department(
                code=data["code"],
                name=data["name"],
                description=data["description"],
            )
            db.add(dept)
            db.flush()  # get the id before commit so we can put it in dept_map
            dept_map[data["code"]] = dept
            inserted += 1
            print(f"  [add]  Department '{data['code']}' — {data['name']}")

    db.commit()
    print(f"\nDepartments: {inserted} inserted, {len(DEPARTMENTS) - inserted} already existed.\n")
    return dept_map


# ---------------------------------------------------------------------------
# Super admin creation
# ---------------------------------------------------------------------------

def create_super_admin(db, dept_map: dict[str, Department]) -> None:
    """
    Interactively creates the first super_admin account. Skips if one
    already exists — this is intentionally not idempotent for accounts,
    since creating a duplicate super_admin is a meaningful mistake.
    """
    existing_admin = db.query(User).filter(User.role == "super_admin").first()
    if existing_admin:
        print(f"A super_admin account already exists ({existing_admin.email}). Skipping.")
        return

    print("=== Create initial super_admin account ===")
    full_name = input("Full name: ").strip()
    email = input("Email: ").strip().lower()
    password = getpass.getpass("Password (min 8 chars): ")
    password_confirm = getpass.getpass("Confirm password: ")

    if not full_name or not email:
        print("ERROR: full_name and email are required.")
        sys.exit(1)

    if len(password) < 8:
        print("ERROR: Password must be at least 8 characters.")
        sys.exit(1)

    if password != password_confirm:
        print("ERROR: Passwords do not match.")
        sys.exit(1)

    existing_email = db.query(User).filter(User.email == email).first()
    if existing_email:
        print(f"ERROR: A user with email '{email}' already exists.")
        sys.exit(1)

    # Super admins are not scoped to a department — department_id stays None.
    # If you want to tag the super_admin to CITE specifically, change None
    # to dept_map.get("CITE") and use .id below.
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


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

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
        dept_map = seed_departments(db)

        if args.create_admin:
            print("--- Creating super_admin ---")
            create_super_admin(db, dept_map)
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
