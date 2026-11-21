"""An SAP proposal nobody decided by 30 days before the activity is rejected by the system."""
import logging
import threading
from datetime import timedelta

from app.models import Event
from app.models_sap import SAPProposal
from app.services import sap
from app.services.approvals import record_decision
from app.services.closure import institution_today

WAITING = ('pending_department_review', 'pending_sap_review')
REASON = 'Rejected automatically: no decision was made 30 days before the activity.'
logger = logging.getLogger(__name__)


def reject_undecided_proposals(db, today=None) -> int:
    """Reject proposals still waiting on the Moderator, the Dean or the SDS Office with under 30 days left.

    Matches the submit rule (at least 30 days ahead), so a proposal sent on the last allowed day
    is left alone that day. Returns how many were rejected."""
    cutoff = (today or institution_today()) + timedelta(days=30)
    due = (db.query(SAPProposal.id, SAPProposal.event_id).join(Event, Event.id == SAPProposal.event_id)
           .filter(SAPProposal.state.in_(WAITING), Event.event_date < cutoff).all())
    db.rollback()  # the read holds nothing; each proposal gets its own locked transaction
    rejected = 0
    for proposal_id, event_id in due:
        try:
            event = db.query(Event).filter_by(id=event_id).with_for_update().first()
            # Read after the lock, the way reviewers do: one may have just decided it.
            proposal = db.get(SAPProposal, proposal_id, populate_existing=True)
            if proposal.state not in WAITING or event.event_date is None or event.event_date >= cutoff:
                db.rollback()
                continue
            with_sds = proposal.state == 'pending_sap_review'
            proposal.state, event.status, proposal.return_remarks = 'rejected', 'rejected', REASON
            record_decision(db, 'event', event.id, 'rejected', None, REASON)
            sap.save(db, event, proposal, None, 'sap_auto_rejected', notify=True, notify_sds=with_sds,
                     details={'proposal_id': str(proposal.id), 'revision': proposal.revision_no, 'remarks': REASON})
            rejected += 1
        except Exception:
            db.rollback()
            logger.exception("Could not auto-reject SAP proposal %s", proposal_id)
    return rejected


def start_deadline_check(session_factory, every: timedelta = timedelta(hours=1)) -> None:
    # shortcut: in-process timer only runs while the server is awake; it catches up on wake since the check is by date.
    def loop():
        while True:
            db = session_factory()
            try:
                count = reject_undecided_proposals(db)
                if count:
                    logger.info("Auto-rejected %d SAP proposals with no decision 30 days before the activity", count)
            except Exception:
                logger.exception("SAP deadline check crashed")
            finally:
                db.close()
            threading.Event().wait(every.total_seconds())

    threading.Thread(target=loop, name="sap-deadline", daemon=True).start()
