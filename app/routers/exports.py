"""Frontend-ready exports reuse existing report queries and their RBAC checks."""
import uuid
from datetime import date
from typing import Literal
from fastapi import APIRouter, Depends, Response
from sqlalchemy.orm import Session
from app.database import get_db
from app.dependencies import require_operational_read
from app.models import User
from app.routers.analytics import get_dashboard
from app.routers.reports import get_event_report, get_category_report, get_consolidated_financial_report
from app.schemas import Semester, EventScope
from app.services.report_exports import render_export

router = APIRouter(prefix="/reports", tags=["report downloads"])
ExportFormat = Literal["csv", "pdf", "html"]
EXPORT_RESPONSES = {200: {"description": "Downloadable report or print-ready HTML", "content": {
    "application/pdf": {"schema": {"type": "string", "format": "binary"}},
    "text/csv": {"schema": {"type": "string"}},
    "text/html": {"schema": {"type": "string"}},
}}}


def summary_section(report, excluded=()):
    values = report.model_dump(mode="json")
    return ("Summary", ["Field", "Value"], [
        [key.replace("_", " ").title(), value] for key, value in values.items()
        if key not in excluded and not isinstance(value, (dict, list))])


def income_source_section(report):
    return ("Income by source (excludes pending/rejected receipt reviews)",
            ["Type", "Source", "Count", "Income (PHP)"],
            [[s.source_type, s.source, s.income_count, s.total_income] for s in report.income_by_source])


@router.get("/dashboard/export", response_class=Response, responses=EXPORT_RESPONSES)
def export_dashboard(format: ExportFormat = "pdf", db: Session = Depends(get_db),
                     current_user: User = Depends(require_operational_read)):
    report = get_dashboard(db=db, current_user=current_user)
    sections = [summary_section(report)]
    sections += [(name.replace("_", " ").title(), ["Status", "Count"], list(values.items()))
                 for name, values in report.model_dump().items() if isinstance(values, dict)]
    return render_export("SMARTEVENT Dashboard", sections, format, "smartevent-dashboard")


@router.get("/event/{event_id}/export", response_class=Response, responses=EXPORT_RESPONSES)
def export_event(event_id: uuid.UUID, format: ExportFormat = "pdf", db: Session = Depends(get_db),
                 current_user: User = Depends(require_operational_read)):
    report = get_event_report(event_id=event_id, db=db, current_user=current_user)
    sections = [summary_section(report),
                ("Income", ["Date", "Source", "Purpose", "Receipt review", "Amount (PHP)"],
                 [[i.received_on, i.source, i.purpose, i.receipt_review_status, i.amount] for i in report.incomes]),
                ("Expenses (only approved expenses count toward totals)",
                 ["ID", "Date", "Description", "Status", "Amount (PHP)"],
                 [[str(e.id), e.expense_date, e.description, e.status, e.amount] for e in report.expenses])]
    sections.append(income_source_section(report))
    sections.append(("Receipts", ["Transaction", "Purpose", "Merchant", "Number", "Review"],
        [[str(r.expense_id or r.income_id), r.purpose, r.merchant, r.receipt_number, r.review_status] for r in report.receipts]))
    return render_export("SMARTEVENT Event Report", sections, format, f"smartevent-event-{event_id}")


@router.get("/category/{category_id}/export", response_class=Response, responses=EXPORT_RESPONSES)
def export_category(category_id: uuid.UUID, format: ExportFormat = "pdf", db: Session = Depends(get_db),
                    current_user: User = Depends(require_operational_read)):
    report = get_category_report(category_id=category_id, db=db, current_user=current_user)
    return render_export("SMARTEVENT Category Report", [summary_section(report)], format, f"smartevent-category-{category_id}")


@router.get("/financial/export", response_class=Response, responses=EXPORT_RESPONSES)
def export_financial(period: Literal["weekly", "monthly", "school_year", "semester"],
                     format: ExportFormat = "pdf", reference_date: date | None = None,
                     school_year: str | None = None, semester: Semester | None = None,
                     event_scope: EventScope | None = None, db: Session = Depends(get_db),
                     current_user: User = Depends(require_operational_read)):
    report = get_consolidated_financial_report(period=period, reference_date=reference_date,
        school_year=school_year, semester=semester, event_scope=event_scope, db=db, current_user=current_user)
    sections = [summary_section(report),
                ("Events", ["Event", "School year", "Semester", "Scope", "Income (PHP)", "Expenses (PHP)", "Balance (PHP)"],
                 [[e.title, e.school_year, e.semester, e.event_scope, e.total_income, e.total_expenses, e.net_balance] for e in report.events])]
    sections.append(income_source_section(report))
    return render_export("SMARTEVENT Financial Report", sections, format, "smartevent-financial-report")
