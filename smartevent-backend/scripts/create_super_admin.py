"""Create a Super Admin with python -m scripts.create_super_admin."""

import sys
from pydantic import EmailStr, TypeAdapter, ValidationError
from sqlalchemy import func

from app.database import SessionLocal
from app.models import User
from app.services.account_provisioning import create_user_with_temp_password
from app.services.email import EmailError


def main() -> None:
    full_name = input("Full name: ").strip()
    email = input("Email: ").strip().lower()

    try:
        email = TypeAdapter(EmailStr).validate_python(email)
        if not 1 <= len(full_name) <= 150 or len(email) > 150:
            raise ValueError
    except (ValidationError, ValueError):
        print("A valid full name and email are required.", file=sys.stderr)
        sys.exit(1)

    db = SessionLocal()
    try:
        existing = db.query(User).filter(func.lower(User.email) == email).first()
        if existing:
            print(f"A user with email '{email}' already exists.", file=sys.stderr)
            sys.exit(1)

        user = create_user_with_temp_password(
            db,
            full_name=full_name,
            email=email,
            role="super_admin",
        )
        db.commit()
        print(f"\nSuper Admin account created: {user.email}")
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
