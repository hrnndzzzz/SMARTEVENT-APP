"""Seed a demo organization with real accounts, so a demo can exercise the server.

    python -m scripts.seed_demo_org              # create or top up
    python -m scripts.seed_demo_org --remove     # take it all back out
    python -m scripts.seed_demo_org --show       # print the accounts again

The app's built-in demo mode talks to nothing: it fills the screens from
`demo_data.dart` and never opens a socket. That is the right thing for a
recording, and the wrong thing for showing that the backend exists. This
makes the other kind of demo — ordinary accounts on the live server, with
enough history behind them that every screen has something to say.

What it makes, all of it prefixed `DEMO`:

  * one organization, DEMO-ORG, in the CITE department
  * three accounts: officer, adviser, admin — one of each desk a proposal
    passes, so the approval chain can be walked in front of a panel
  * three budget categories, one deliberately near its low-balance line
  * four past events, approved or completed, each with recorded spending

The four past events are not decoration. The AI budget suggestion reads up
to thirty approved or completed events and returns nothing at all below
two, so a fresh organization makes that feature look broken. Their spending
is deliberately uneven, so the suggestion has something to reason from.

Roles: officer, adviser and admin only. Treasurer and signatory are being
removed, and this seed has to work on either side of that change.

Passwords are generated here and printed once. They are not stored in the
repository and not shipped in the app: anything committed to an APK is
readable by anyone who downloads it. Write them down when the script
prints them, or run --show, which re-prints the accounts and resets their
passwords to freshly generated ones.
"""

import argparse
import secrets
import string
import sys
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy import func

from app.database import SessionLocal
from app.models import Category, Department, Event, Expense, Organization, User
from app.security import hash_password

ORG_CODE = "DEMO-ORG"
ORG_NAME = "DEMO Society for Demonstrations"
EMAIL_DOMAIN = "demo.smartevent.local"

# Only roles that survive the treasurer/signatory removal.
ACCOUNTS = [
    ("officer", "Demo Officer", "DEMO Officer (Treasurer)"),
    ("adviser", "Demo Adviser", "DEMO Moderator"),
    ("admin", "Demo Dean", "DEMO Dean"),
]

CATEGORIES = [
    # name, allocated, remaining, low-balance line
    ("DEMO Supplies", "20000.00", "12400.00", "5000.00"),
    ("DEMO Honoraria", "15000.00", "9000.00", "3000.00"),
    # Sits under its threshold on purpose: the low-balance notice needs
    # something to fire on, and an empty demo never shows it.
    ("DEMO Venue and Logistics", "18000.00", "1800.00", "4000.00"),
]

# title, description, budget, actual spend, days ago, status, semester
#
# Every event also carries school year, semester and scope: the database
# requires all three (`events_academic_metadata_required`), and a row
# without them is rejected outright. Spending stays under the budget
# because `chk_event_remaining_budget_nonnegative` forbids a negative
# remainder — an overspent event cannot be represented here at all. The
# ratios are uneven on purpose, so the budget suggestion has a spread to
# reason from rather than one flat percentage.
PAST_EVENTS = [
    ("DEMO Programming Bootcamp", "Two-day introduction to Python for first years.",
     "12000.00", "11250.00", 210, "completed", "2nd"),
    ("DEMO IT Week General Assembly", "Opening assembly with guest speakers.",
     "8000.00", "7400.00", 150, "completed", "2nd"),
    ("DEMO Capstone Showcase", "Exhibition of fourth-year capstone projects.",
     "15000.00", "14250.00", 90, "completed", "1st"),
    ("DEMO Leadership Seminar", "Officer training for the incoming term.",
     "6000.00", "4900.00", 45, "approved", "1st"),
]


def _school_year(day: date) -> str:
    """The academic year a date falls in, as `YYYY-YYYY`.

    The database checks the shape and that the second year is the first
    plus one. June starts a new year here, which is close enough for
    seeded history and keeps every row inside one academic year.
    """
    start = day.year if day.month >= 6 else day.year - 1
    return f"{start}-{start + 1}"


def _password() -> str:
    """Readable enough to type off a screen, long enough not to be guessed."""
    alphabet = string.ascii_lowercase + string.digits
    return "Demo-" + "".join(secrets.choice(alphabet) for _ in range(10))


def _demo_users(db):
    return db.query(User).filter(User.email.like(f"%@{EMAIL_DOMAIN}")).all()


def _org(db):
    return db.query(Organization).filter(Organization.code == ORG_CODE).first()


def remove(db) -> None:
    organization = _org(db)
    users = _demo_users(db)
    if organization is None and not users:
        print("Nothing to remove: no demo organization and no demo accounts.")
        return

    if organization is not None:
        events = db.query(Event).filter(Event.organization_id == organization.id).all()
        event_ids = [event.id for event in events]
        if event_ids:
            deleted = (db.query(Expense).filter(Expense.event_id.in_(event_ids))
                       .delete(synchronize_session=False))
            print(f"  expenses       {deleted}")
        print(f"  events         {len(events)}")
        for event in events:
            db.delete(event)
        categories = db.query(Category).filter(Category.organization_id == organization.id).all()
        print(f"  categories     {len(categories)}")
        for category in categories:
            db.delete(category)

    print(f"  accounts       {len(users)}")
    for user in users:
        db.delete(user)

    if organization is not None:
        db.delete(organization)
        print(f"  organization   {ORG_CODE}")

    db.commit()
    print("\nRemoved. Nothing outside the DEMO prefix was touched.\n")


def show(db) -> None:
    """Re-issue the passwords. The old ones are hashed, so they cannot be read back."""
    users = _demo_users(db)
    if not users:
        print("No demo accounts exist yet. Run without --remove or --show to make them.")
        return
    print("\nDemo accounts — new passwords, the previous ones stop working:\n")
    for user in sorted(users, key=lambda u: u.role):
        password = _password()
        user.password_hash = hash_password(password)
        user.must_change_password = False
        user.login_failed_attempts = 0
        user.login_locked_until = None
        print(f"  {user.role:<8} {user.email:<34} {password}")
    db.commit()
    print()


def seed(db) -> None:
    department = db.query(Department).filter(Department.code == "CITE").first()
    if department is None:
        print("No CITE department. Run scripts.seed_initial_data first.", file=sys.stderr)
        sys.exit(1)

    organization = _org(db)
    if organization is None:
        organization = Organization(code=ORG_CODE, name=ORG_NAME, department_id=department.id)
        db.add(organization)
        db.flush()
        print(f"  [add]  organization {ORG_CODE}")
    else:
        print(f"  [skip] organization {ORG_CODE} already exists")

    issued = []
    accounts = {}
    for role, full_name, position in ACCOUNTS:
        email = f"demo.{role}@{EMAIL_DOMAIN}"
        user = db.query(User).filter(func.lower(User.email) == email).first()
        password = _password()
        if user is None:
            user = User(
                full_name=full_name, email=email, role=role, position=position,
                department_id=department.id, organization_id=organization.id,
                password_hash=hash_password(password), is_active=True,
                is_suspended=False, must_change_password=False,
            )
            db.add(user)
            db.flush()
            print(f"  [add]  {role:<8} {email}")
        else:
            # Topping up an existing seed: the hash cannot be read back, so
            # the only way to hand over a working password is to set a new one.
            user.password_hash = hash_password(password)
            user.must_change_password = False
            user.is_active = True
            user.is_suspended = False
            user.login_failed_attempts = 0
            user.login_locked_until = None
            print(f"  [reset] {role:<7} {email}")
        accounts[role] = user
        issued.append((role, email, password))

    officer = accounts["officer"]
    admin = accounts["admin"]

    categories = {}
    for name, allocated, remaining, threshold in CATEGORIES:
        category = (db.query(Category)
                    .filter(Category.organization_id == organization.id, Category.name == name)
                    .first())
        if category is None:
            category = Category(
                name=name, organization_id=organization.id, department_id=department.id,
                allocated_budget=Decimal(allocated), remaining_budget=Decimal(remaining),
                low_balance_threshold=Decimal(threshold), created_by=admin.id,
            )
            db.add(category)
            db.flush()
            print(f"  [add]  category {name}")
        categories[name] = category

    supplies = categories["DEMO Supplies"]
    for title, description, budget, spend, days_ago, status, semester in PAST_EVENTS:
        event = (db.query(Event)
                 .filter(Event.organization_id == organization.id, Event.title == title)
                 .first())
        if event is not None:
            print(f"  [skip] event {title}")
            continue
        when = date.today() - timedelta(days=days_ago)
        event = Event(
            title=title, description=description, status=status,
            school_year=_school_year(when), semester=semester,
            event_scope="organizational",
            organization_id=organization.id, department_id=department.id,
            proposed_by=officer.id, event_date=when,
            allocated_budget=Decimal(budget),
            remaining_budget=Decimal(budget) - Decimal(spend),
            estimated_cost=Decimal(budget),
            completed_on=when if status == "completed" else None,
            completed_by=admin.id if status == "completed" else None,
        )
        db.add(event)
        db.flush()
        # Approved, because that is the only status the budget suggestion counts.
        db.add(Expense(
            description=f"{title} — recorded spending",
            amount=Decimal(spend), expense_date=when, status="approved",
            event_id=event.id, category_id=supplies.id,
            organization_id=organization.id, department_id=department.id,
            recorded_by=officer.id,
        ))
        print(f"  [add]  event {title} ({status}, spent {spend})")

    db.commit()

    print("\nDemo accounts — write these down, they are printed once:\n")
    for role, email, password in issued:
        print(f"  {role:<8} {email:<34} {password}")
    print("""
All of it is prefixed DEMO. To take it back out:

    python -m scripts.seed_demo_org --remove
""")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--remove", action="store_true",
                       help="delete the demo organization, its accounts and their records")
    group.add_argument("--show", action="store_true",
                       help="re-issue and print the demo passwords")
    args = parser.parse_args()

    db = SessionLocal()
    try:
        if args.remove:
            remove(db)
        elif args.show:
            show(db)
        else:
            seed(db)
    finally:
        db.close()


if __name__ == "__main__":
    main()
