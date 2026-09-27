"""
Manual Super Admin account creation — run this directly, NOT through
the API. This exists specifically so future school IT staff (after
graduation) can create their own admin account without needing an
existing admin's token or hand-writing raw SQL with an Argon2 hash.

Usage (from the project root, with the venv active and .env present):

    python -m scripts.create_super_admin

It will prompt for a full name and email, create the account with a
fresh OTP as its temporary password (same as every other account in
this system), and email that OTP via the same Resend config the
rest of the app uses — see RESEND_API_KEY / RESEND_FROM_EMAIL in .env.

Requires direct database access (the same DATABASE_URL the app uses)
and Resend to already be configured — this is a maintenance tool
run on a machine that already has the project's .env, not something
exposed to the internet.
"""

import sys

from app.database import SessionLocal
from app.models import User
from app.services.account_provisioning import create_user_with_temp_password
from app.services.email import EmailError


def main() -> None:
    full_name = input("Full name: ").strip()
    email = input("Email: ").strip()

    if not full_name or not email:
        print("Full name and email are both required.", file=sys.stderr)
        sys.exit(1)

    db = SessionLocal()
    try:
        existing = db.query(User).filter(User.email == email).first()
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
