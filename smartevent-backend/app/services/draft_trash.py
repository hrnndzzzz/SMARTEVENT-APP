"""Deleted drafts are kept whole for 30 days, then removed for good with their files."""
import logging
from datetime import datetime, timedelta, timezone

from app.models import DeletedEvent
from app.services import storage

KEEP = timedelta(days=30)
BATCH = 100
logger = logging.getLogger(__name__)


def purge_deleted_drafts(db, now: datetime | None = None) -> int:
    """Removes drafts deleted more than 30 days ago; returns how many."""
    cutoff = (now or datetime.now(timezone.utc)) - KEEP
    purged = 0
    while True:
        rows = (db.query(DeletedEvent).filter(DeletedEvent.deleted_at < cutoff)
                .order_by(DeletedEvent.deleted_at).limit(BATCH).all())
        if not rows:
            return purged
        refs = [ref for row in rows for ref in (row.storage_refs or [])]
        try:
            if refs:
                storage.delete_uploaded_file(refs)
        except (storage.StorageError, RuntimeError) as exc:
            # Rows stay so the next run retries their files.
            logger.warning("Deleted draft cleanup failed: %s", exc)
            db.rollback()
            return purged
        for row in rows:
            db.delete(row)
        db.commit()
        purged += len(rows)
