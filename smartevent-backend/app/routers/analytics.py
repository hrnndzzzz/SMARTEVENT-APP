import logging
import uuid
from functools import lru_cache

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.dependencies import require_operational_read, require_role, scope_query_by_department
from app.models import Approval, AuditLog, Category, Event, Expense, Inventory, User
from app.models_sap import SAPProposal, SAPReview, SAPRevision
from app.schemas import DashboardSummary, ExpenseOut, SpendingTrendPoint
from app.services import ocr

router = APIRouter(prefix="/analytics", tags=["analytics"])
logger = logging.getLogger(__name__)


@router.get("/dashboard/exports")
def dashboard_exports(current_user: User = Depends(require_operational_read)):
    """Relative URLs: fetch with Authorization, then save/print response bytes."""
    return {
        "formats": {"pdf": "application/pdf", "csv": "text/csv", "html": "text/html"},
        "dashboard": {fmt: f"/reports/dashboard/export?format={fmt}" for fmt in ("pdf", "csv", "html")},
        "event_url_template": "/reports/event/{event_id}/export?format={format}",
        "category_url_template": "/reports/category/{category_id}/export?format={format}",
        "financial_url_template": "/reports/financial/export?period={period}&format={format}",
        "financial_filters": ["reference_date", "school_year", "semester", "event_scope", "organization_id"],
        "authorization": "Bearer token required on every export request; do not put tokens in URLs",
    }


def for_organization(query, model, organization_id: uuid.UUID | None):
    """Narrow an already-scoped query; an organization outside the caller's scope yields nothing."""
    return query if organization_id is None else query.filter(model.organization_id == organization_id)


@router.get("/dashboard", response_model=DashboardSummary)
def get_dashboard(
    organization_id: uuid.UUID | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    def scoped(model):
        query = scope_query_by_department(db.query(model), model.department_id, current_user)
        return for_organization(query, model, organization_id)

    category_query = scoped(Category)
    event_query = scoped(Event)
    expense_query = scoped(Expense)

    total_categories = category_query.count()
    allocated_sum, remaining_sum = category_query.with_entities(
        func.coalesce(func.sum(Category.allocated_budget), 0),
        func.coalesce(func.sum(Category.remaining_budget), 0),
    ).first()

    events_by_status = dict(
        event_query.with_entities(Event.status, func.count(Event.id)).group_by(Event.status).all()
    )
    expenses_by_status = dict(
        expense_query.with_entities(Expense.status, func.count(Expense.id)).group_by(Expense.status).all()
    )

    flagged_expense_count = expense_query.filter(Expense.is_flagged.is_(True)).count()
    inventory_query = scoped(Inventory).filter(Inventory.is_archived.is_(False))
    low_stock_item_count = inventory_query.filter(
        Inventory.quantity <= Inventory.low_stock_threshold
    ).count()
    draft_inventory_count = inventory_query.filter(Inventory.is_draft.is_(True)).count()

    return DashboardSummary(
        total_categories=total_categories,
        total_allocated_budget=float(allocated_sum),
        total_remaining_budget=float(remaining_sum),
        events_by_status=events_by_status,
        expenses_by_status=expenses_by_status,
        flagged_expense_count=flagged_expense_count,
        low_stock_item_count=low_stock_item_count,
        draft_inventory_count=draft_inventory_count,
    )


class ProposalSummary(BaseModel):
    accepted: str | None = None
    rejected: str | None = None


class _SummaryText(BaseModel):
    accepted: str
    rejected: str


_REMARKS_PER_SIDE = 40
_REMARK_LENGTH = 500
_SUMMARY_PROMPT = """You read reviewers' remarks on student-organization event proposals at a school.
Write two short summaries in plain English, 2 to 3 sentences each:
- "accepted": what the accepted proposals did well, judging from the approving remarks.
- "rejected": the most common reasons proposals were rejected or returned for changes.
Name patterns, not individual proposals or people. If a side has no remarks, say there is nothing to go on yet.

Remarks on accepted proposals:
{accepted}

Remarks on rejected or returned proposals:
{rejected}
"""


@lru_cache(maxsize=64)
def _summarise(accepted: tuple[str, ...], rejected: tuple[str, ...]) -> ProposalSummary:
    """Cached on the remarks themselves, so Gemini is asked again only when a new decision lands."""
    lines = lambda remarks: "\n".join(f"- {r}" for r in remarks) or "(none)"
    parsed = ocr._generate(_SUMMARY_PROMPT.format(accepted=lines(accepted), rejected=lines(rejected)), _SummaryText)

    def text(key, remarks):
        if not remarks:  # nothing was read, so nothing the model wrote is a summary
            return None
        return str(parsed.get(key) or "").strip()[:1000] or None

    return ProposalSummary(accepted=text("accepted", accepted), rejected=text("rejected", rejected))


@router.get("/proposal-summary", response_model=ProposalSummary)
def get_proposal_summary(
    organization_id: uuid.UUID | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    """An AI-written reading of reviewers' remarks: what gets proposals accepted, and what gets them rejected.

    Only remark text is sent to Gemini, never names, titles or emails. Nulls when there is nothing to read,
    no key, or Gemini fails; the app still shows the counts from /analytics/dashboard."""
    events = for_organization(
        scope_query_by_department(db.query(Event.id), Event.department_id, current_user), Event, organization_id
    ).subquery()
    event_ids = db.query(events.c.id)

    accepted, rejected = [], []
    # Adviser and Dean decisions, including the Moderator's and Dean's SAP returns.
    for decision, remarks in (
        db.query(Approval.decision, Approval.remarks)
        .filter(Approval.entity_type == "event", Approval.entity_id.in_(event_ids))
        .order_by(Approval.decided_at.desc())
    ):
        if (remarks or "").strip():
            (accepted if decision == "approved" else rejected).append(remarks)
    # The SDS Office's returns and rejections carry their remarks in the audit entry.
    for (details,) in (
        db.query(AuditLog.details)
        .filter(AuditLog.action.in_(("sap_returned", "sap_rejected")), AuditLog.entity_id.in_(event_ids))
        .order_by(AuditLog.created_at.desc())
    ):
        if isinstance(details, dict) and str(details.get("remarks") or "").strip():
            rejected.append(details["remarks"])
    # The SDS Office's signed reviews are its approvals.
    for (remarks,) in (
        db.query(SAPReview.overall_remarks)
        .join(SAPRevision, SAPRevision.id == SAPReview.revision_id)
        .join(SAPProposal, SAPProposal.id == SAPRevision.proposal_id)
        .filter(SAPReview.signed_at.isnot(None), SAPProposal.event_id.in_(event_ids))
        .order_by(SAPReview.signed_at.desc())
    ):
        if (remarks or "").strip():
            accepted.append(remarks)

    trim = lambda remarks: tuple(r.strip()[:_REMARK_LENGTH] for r in remarks[:_REMARKS_PER_SIDE])
    accepted, rejected = trim(accepted), trim(rejected)
    if not settings.gemini_api_key or not (accepted or rejected):
        return ProposalSummary()
    try:
        return _summarise(accepted, rejected)
    except Exception:  # an optional summary: a Gemini outage must not fail the dashboard
        logger.warning("Proposal summary could not be written", exc_info=True)
        return ProposalSummary()


@router.get("/spending-trends", response_model=list[SpendingTrendPoint])
def get_spending_trends(
    months: int = Query(6, ge=1, le=120),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_operational_read),
):
    month_expr = func.date_trunc("month", Expense.created_at)

    expense_query = scope_query_by_department(
        db.query(Expense), Expense.department_id, current_user
    )
    rows = (
        expense_query.with_entities(
            month_expr.label("month"),
            func.coalesce(func.sum(Expense.amount), 0).label("total"),
            func.count(Expense.id).label("count"),
        )
        .filter(Expense.status == "approved")
        .group_by(month_expr)
        .order_by(month_expr.desc())
        .limit(months)
        .all()
    )

    return [
        SpendingTrendPoint(
            month=row.month.strftime("%Y-%m"),
            total_amount=float(row.total),
            expense_count=row.count,
        )
        for row in reversed(rows)
    ]


@router.get("/threats", response_model=list[ExpenseOut])
def get_flagged_expenses(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("adviser", "officer", "admin")),
):
    query = scope_query_by_department(
        db.query(Expense), Expense.department_id, current_user
    )
    return (
        query
        .filter(Expense.is_flagged.is_(True))
        .order_by(Expense.created_at.desc())
        .all()
    )
