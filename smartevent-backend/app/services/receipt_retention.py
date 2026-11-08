"""Receipt photos are deleted from storage 30 days after upload; the receipt record stays."""
import logging
import threading
from datetime import datetime, timedelta, timezone

from app.config import settings
from app.models import Receipt
from app.services.storage import StorageError, delete_uploaded_file, storage_object

RETENTION = timedelta(days=30)
BATCH = 200
logger = logging.getLogger(__name__)


def _ours(ref: str) -> bool:
    try:
        return storage_object(ref, settings.supabase_receipts_bucket) is not None
    except ValueError:
        return False


def purge_old_receipt_files(db, now: datetime | None = None) -> int:
    """Delete photos of receipts older than 30 days; returns how many receipts were marked."""
    cutoff = (now or datetime.now(timezone.utc)) - RETENTION
    purged = 0
    while True:
        rows = (db.query(Receipt).filter(Receipt.created_at < cutoff, Receipt.file_deleted_at.is_(None))
                .order_by(Receipt.created_at).limit(BATCH).all())
        if not rows:
            return purged
        # A link outside our bucket has nothing of ours to delete; it is only marked.
        refs = [row.receipt_url for row in rows if _ours(row.receipt_url)]
        try:
            if refs:
                delete_uploaded_file(refs, settings.supabase_receipts_bucket)
        except (StorageError, RuntimeError) as exc:
            # Rows stay unmarked so the next run retries them.
            logger.warning("Receipt photo cleanup failed: %s", exc)
            db.rollback()
            return purged
        stamp = datetime.now(timezone.utc)
        for row in rows:
            row.file_deleted_at = stamp
        db.commit()
        purged += len(rows)


def start_receipt_cleanup(session_factory, every: timedelta = timedelta(days=1)) -> None:
    # shortcut: in-process timer only runs while the server is awake; move to a scheduled job if the host sleeps for days.
    def loop():
        while True:
            db = session_factory()
            try:
                count = purge_old_receipt_files(db)
                if count:
                    logger.info("Removed %d receipt photos older than 30 days", count)
            except Exception:
                logger.exception("Receipt photo cleanup crashed")
            finally:
                db.close()
            threading.Event().wait(every.total_seconds())

    threading.Thread(target=loop, name="receipt-cleanup", daemon=True).start()
