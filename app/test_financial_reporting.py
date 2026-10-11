from datetime import date
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.database import get_db
from app.dependencies import require_active_account
from app.main import app
from app.schemas import (
    ConsolidatedFinancialReport,
    ExpenseCreate,
    FinancialEventSummary,
    IncomeCreate,
)
from app.routers.reports import (
    _calendar_window,
    _render_financial_report_pdf,
    get_consolidated_financial_report,
)
from app.routers import reports as reports_router


def test_income_requires_event_source_purpose_and_positive_amount():
    payload = IncomeCreate(
        event_id=uuid4(),
        source="Sponsorship",
        purpose="Venue support",
        amount=2500,
        received_on=date(2026, 9, 1),
    )

    assert payload.source == "Sponsorship"
    assert payload.received_on == date(2026, 9, 1)

    with pytest.raises(ValidationError):
        IncomeCreate(event_id=uuid4(), source="", purpose="", amount=0)


def test_expense_date_defaults_for_existing_api_clients():
    payload = ExpenseCreate(
        category_id=uuid4(),
        description="Venue deposit",
        amount=500,
    )

    assert payload.expense_date == date.today()


def test_weekly_window_uses_monday_through_sunday():
    assert _calendar_window("weekly", date(2026, 9, 27)) == (
        date(2026, 9, 21),
        date(2026, 9, 27),
    )


def test_monthly_window_includes_last_day():
    assert _calendar_window("monthly", date(2024, 2, 12)) == (
        date(2024, 2, 1),
        date(2024, 2, 29),
    )


def test_school_year_report_requires_school_year():
    with pytest.raises(HTTPException) as exc_info:
        get_consolidated_financial_report(
            period="school_year",
            reference_date=None,
            school_year=None,
            semester=None,
            event_scope=None,
            db=None,
            current_user=None,
        )

    assert exc_info.value.status_code == 422


def test_semester_report_requires_semester():
    with pytest.raises(HTTPException) as exc_info:
        get_consolidated_financial_report(
            period="semester",
            reference_date=None,
            school_year="2026-2027",
            semester=None,
            event_scope=None,
            db=None,
            current_user=None,
        )

    assert exc_info.value.status_code == 422


def test_financial_report_pdf_has_valid_pdf_structure():
    report = ConsolidatedFinancialReport(
        period="school_year",
        start_date=None,
        end_date=None,
        school_year="2026-2027",
        semester=None,
        event_scope="departmental",
        total_income=1000,
        total_expenses=350,
        unassigned_expense_total=0,
        net_balance=650,
        events=[
            FinancialEventSummary(
                event_id=uuid4(),
                title="Student Leadership Seminar",
                school_year="2026-2027",
                semester="1st",
                event_scope="departmental",
                income_count=1,
                expense_count=1,
                total_income=1000,
                total_expenses=350,
                net_balance=650,
            )
        ],
    )

    pdf_bytes = _render_financial_report_pdf(report)

    assert pdf_bytes.startswith(b"%PDF-")
    assert b"%%EOF" in pdf_bytes[-32:]
    assert len(pdf_bytes) > 1000


def test_pdf_endpoint_returns_download_and_forwards_filters(monkeypatch):
    report = ConsolidatedFinancialReport(
        period="semester",
        start_date=None,
        end_date=None,
        school_year="2026-2027",
        semester="1st",
        event_scope="organizational",
        total_income=0,
        total_expenses=0,
        unassigned_expense_total=0,
        net_balance=0,
        events=[],
    )
    forwarded = {}

    def fake_get_report(**kwargs):
        forwarded.update(kwargs)
        return report

    monkeypatch.setattr(reports_router, "get_consolidated_financial_report", fake_get_report)
    original_overrides = app.dependency_overrides.copy()
    app.dependency_overrides[require_active_account] = lambda: SimpleNamespace(
        role="admin",
        department_id=uuid4(),
        organization_id=uuid4(),
        must_change_password=False,
    )
    app.dependency_overrides[get_db] = lambda: None

    try:
        response = TestClient(app).get(
            "/reports/financial.pdf?period=semester&school_year=2026-2027"
            "&semester=1st&event_scope=organizational"
        )
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(original_overrides)

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/pdf")
    assert "attachment; filename=\"smartevent-financial-report.pdf\"" in response.headers["content-disposition"]
    assert response.content.startswith(b"%PDF-")
    assert forwarded["school_year"] == "2026-2027"
    assert forwarded["semester"] == "1st"
    assert forwarded["event_scope"] == "organizational"
