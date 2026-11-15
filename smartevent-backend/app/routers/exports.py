"""Frontend-ready exports reuse existing report queries and their RBAC checks."""
import uuid
from collections import defaultdict
from datetime import date
from typing import Literal
from fastapi import APIRouter, Depends, Response
from sqlalchemy.orm import Session
from app.database import get_db
from app.dependencies import require_operational_read
from app.models import Organization, User
from app.routers.analytics import get_dashboard
from app.routers.reports import get_event_report, get_category_report, get_consolidated_financial_report
from app.schemas import Semester, EventScope
from app.services.academic_year import institution_today
from app.services.report_exports import (
    BRAND, BRAND_TINT, MINT, ORANGE, Chart, financial_sections, income_source_section, pretty, render_export,
)

router = APIRouter(prefix="/reports", tags=["report downloads"])
ExportFormat = Literal["csv", "pdf", "html"]
EXPORT_RESPONSES = {200: {"description": "Downloadable report or print-ready HTML", "content": {
    "application/pdf": {"schema": {"type": "string", "format": "binary"}},
    "text/csv": {"schema": {"type": "string"}},
    "text/html": {"schema": {"type": "string"}},
}}}
PERIODS = {"weekly": "Weekly", "monthly": "Monthly", "school_year": "School year", "semester": "Semester"}
MONTHS = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def _generated():
    return f"Generated {institution_today():%d %b %Y}"


def _organization_line(db, user, organization_id):
    """Names the chosen organization only where the caller's scope reaches it."""
    if organization_id is None:
        return "All organizations in your scope"
    organization = db.get(Organization, organization_id)
    visible = organization is not None and (
        user.role == "super_admin"
        or organization.id == getattr(user, "organization_id", None)
        or (user.role == "admin" and organization.department_id == user.department_id)
    )
    return f"Organization: {organization.name}" if visible else "Organization: outside your scope"


def _bucket(bucket):
    parts = bucket.split("-")
    return MONTHS[int(parts[1]) - 1] if len(parts) == 2 else str(int(parts[2]))


def financial_charts(report):
    budgeted = [e for e in report.events if e.allocated_budget > 0]
    active = [e for e in report.events if e.total_income > 0 or e.total_expenses > 0]
    by_type = defaultdict(float)
    for source in report.income_by_source:
        by_type[source.source_type] += source.total_income
    types = sorted(by_type.items(), key=lambda item: -item[1])
    return [
        Chart("Over time", "line", [_bucket(p.bucket) for p in report.trend],
              [("Income", [p.total_income for p in report.trend], MINT),
               ("Spending", [p.total_expenses for p in report.trend], ORANGE)]),
        Chart("Budget vs actual by event", "bar", [e.title for e in budgeted],
              [("Budget", [e.allocated_budget for e in budgeted], BRAND_TINT),
               ("Spent to date", [e.spent_to_date for e in budgeted], BRAND)],
              alert=tuple(i for i, e in enumerate(budgeted) if e.spent_to_date > e.allocated_budget)),
        Chart("In and out by event", "bar", [e.title for e in active],
              [("In", [e.total_income for e in active], MINT), ("Out", [e.total_expenses for e in active], ORANGE)]),
        Chart("Where it went", "pie", [c.category_name for c in report.expenses_by_category],
              [("Spending", [c.total_expenses for c in report.expenses_by_category], BRAND)]),
        Chart("Where it came from", "pie", [pretty(kind) for kind, _ in types],
              [("Income", [total for _, total in types], BRAND)]),
    ]


def financial_figures(report):
    used = (f"{report.total_spent_to_date / report.total_allocated_budget:.0%}"
            if report.total_allocated_budget > 0 else "No approved budgets")
    figures = [("Income", report.total_income), ("Spending", report.total_expenses),
               ("Net balance", report.net_balance), ("Budget used", used)]
    for label, value in (("Withheld income", report.withheld_income_total),
                         ("General-fund income", report.general_income_total),
                         ("Spending tied to no event", report.unassigned_expense_total)):
        if value:
            figures.append((label, value))
    return figures


@router.get("/dashboard/export", response_class=Response, responses=EXPORT_RESPONSES)
def export_dashboard(format: ExportFormat = "pdf", organization_id: uuid.UUID | None = None,
                     db: Session = Depends(get_db), current_user: User = Depends(require_operational_read)):
    report = get_dashboard(organization_id=organization_id, db=db, current_user=current_user)
    figures = [("Budget categories", report.total_categories), ("Allocated", report.total_allocated_budget),
               ("Spent", report.total_allocated_budget - report.total_remaining_budget),
               ("Remaining", report.total_remaining_budget), ("Flagged expenses", report.flagged_expense_count),
               ("Low-stock items", report.low_stock_item_count), ("Unconfirmed draft items", report.draft_inventory_count)]
    sections = [(pretty(name), ["Status", "Count"], [[pretty(k), v] for k, v in values.items()])
                for name, values in report.model_dump().items() if isinstance(values, dict)]
    return render_export("SMARTEVENT Dashboard", sections, format, "smartevent-dashboard",
                         meta=[_organization_line(db, current_user, organization_id), _generated()], figures=figures)


@router.get("/event/{event_id}/export", response_class=Response, responses=EXPORT_RESPONSES)
def export_event(event_id: uuid.UUID, format: ExportFormat = "pdf", db: Session = Depends(get_db),
                 current_user: User = Depends(require_operational_read)):
    report = get_event_report(event_id=event_id, db=db, current_user=current_user)
    sections = [("Income", ["Date", "Source", "Purpose", "Receipt review", "Amount (PHP)"],
                 [[i.received_on, i.source, i.purpose, pretty(i.receipt_review_status), i.amount] for i in report.incomes]),
                ("Expenses (only approved expenses count toward totals)",
                 ["ID", "Date", "Description", "Status", "Amount (PHP)"],
                 [[str(e.id), e.expense_date, e.description, pretty(e.status), e.amount] for e in report.expenses])]
    sections.append(income_source_section(report))
    sections.append(("Receipts", ["Transaction", "Purpose", "Merchant", "Number", "Review"],
        [[str(r.expense_id or r.income_id), r.purpose, r.merchant, r.receipt_number, pretty(r.review_status)] for r in report.receipts]))
    meta = [report.title, " · ".join(v for v in (pretty(report.status), report.school_year,
                                                  report.semester and f"{report.semester} semester",
                                                  pretty(report.event_scope)) if v), _generated()]
    figures = [("Allocated", report.allocated_budget), ("Estimated cost", report.estimated_cost),
               ("Income", report.total_income), ("Approved spending", report.total_spent),
               ("Remaining budget", report.remaining_budget), ("Net balance", report.net_balance)]
    if report.withheld_income_total:
        figures.append(("Withheld income", report.withheld_income_total))
    spent_colour = "#FF5964" if report.allocated_budget and report.total_spent > report.allocated_budget else BRAND
    by_type = defaultdict(float)
    for source in report.income_by_source:
        by_type[source.source_type] += source.total_income
    charts = [
        Chart("Budget vs spent", "bar", [""],
              [("Allocated", [report.allocated_budget], BRAND_TINT), ("Estimated", [report.estimated_cost], "#3FC8C0"),
               ("Spent", [report.total_spent], spent_colour), ("Income", [report.total_income], MINT)]),
        Chart("Income by source", "pie", [pretty(kind) for kind in by_type], [("Income", list(by_type.values()), BRAND)]),
    ]
    return render_export("SMARTEVENT Event Report", sections, format, f"smartevent-event-{event_id}",
                         meta=meta, figures=figures, charts=charts)


@router.get("/category/{category_id}/export", response_class=Response, responses=EXPORT_RESPONSES)
def export_category(category_id: uuid.UUID, format: ExportFormat = "pdf", db: Session = Depends(get_db),
                    current_user: User = Depends(require_operational_read)):
    report = get_category_report(category_id=category_id, db=db, current_user=current_user)
    figures = [("Allocated", report.allocated_budget), ("Approved spending", report.total_spent),
               ("Remaining", report.remaining_budget), ("Approved expenses", report.approved_expense_count),
               ("Pending expenses", report.pending_expense_count), ("Rejected expenses", report.rejected_expense_count)]
    return render_export("SMARTEVENT Category Report", [], format, f"smartevent-category-{category_id}",
                         meta=[f"Category: {report.category_name}", _generated()], figures=figures)


@router.get("/financial/export", response_class=Response, responses=EXPORT_RESPONSES)
def export_financial(period: Literal["weekly", "monthly", "school_year", "semester"],
                     format: ExportFormat = "pdf", reference_date: date | None = None,
                     school_year: str | None = None, semester: Semester | None = None,
                     event_scope: EventScope | None = None, organization_id: uuid.UUID | None = None,
                     db: Session = Depends(get_db), current_user: User = Depends(require_operational_read)):
    report = get_consolidated_financial_report(period=period, reference_date=reference_date,
        school_year=school_year, semester=semester, event_scope=event_scope, organization_id=organization_id,
        db=db, current_user=current_user)
    window = " to ".join(f"{d:%d %b %Y}" for d in (report.start_date, report.end_date) if d)
    meta = [" · ".join(v for v in (PERIODS.get(report.period, report.period), window, report.school_year,
                                   report.semester and f"{report.semester} semester",
                                   report.event_scope and f"{pretty(report.event_scope)} events") if v),
            _organization_line(db, current_user, organization_id), _generated()]
    return render_export("SMARTEVENT Financial Report", financial_sections(report), format,
                         "smartevent-financial-report", meta=meta, figures=financial_figures(report),
                         charts=financial_charts(report))
