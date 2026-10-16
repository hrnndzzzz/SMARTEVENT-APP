from datetime import datetime, timezone

from app.models import Approval


def record_decision(db, entity_type, entity_id, decision, reviewer, remarks):
    step_order = db.query(Approval).filter(
        Approval.entity_type == entity_type, Approval.entity_id == entity_id,
    ).count() + 1
    db.add(Approval(
        entity_type=entity_type,
        entity_id=entity_id,
        step_order=step_order,
        reviewer_id=reviewer.id,
        decision=decision,
        remarks=remarks,
        decided_at=datetime.now(timezone.utc),
    ))
