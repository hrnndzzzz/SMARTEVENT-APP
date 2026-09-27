"""Retry pending/failed registration emails: python -m scripts.deliver_notifications."""
import argparse
from app.database import SessionLocal
from app.models import Notification
from app.services.notifications import deliver_notification


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=100)
    args = parser.parse_args()
    if args.limit < 1:
        parser.error("--limit must be positive")
    with SessionLocal() as db:
        ids = [row.id for row in db.query(Notification).filter(
            Notification.email_status.in_(["pending", "failed"])
        ).order_by(Notification.created_at).limit(args.limit).all()]
        for notification_id in ids:
            deliver_notification(db, notification_id)


if __name__ == "__main__":
    main()
