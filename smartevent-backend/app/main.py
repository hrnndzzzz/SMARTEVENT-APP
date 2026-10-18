import logging

from fastapi import Depends, FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.dependencies import enforce_read_only
from app.middleware import RequestSecurityMiddleware
from app.routers import (
    analytics,
    audit_logs,
    auth,
    categories,
    cite_members,
    compliance,
    closure,
    departments,
    events,
    exports,
    expenses,
    files,
    inventory,
    incomes,
    organizations,
    notifications,
    proposal_letters,
    recommendations,
    reports,
    receipts,
    sap,
    users,
)

logger = logging.getLogger(__name__)

app = FastAPI(
    title="SMARTEVENT API",
    docs_url="/docs" if settings.app_env == "development" else None,
    redoc_url="/redoc" if settings.app_env == "development" else None,
    openapi_url="/openapi.json" if settings.app_env == "development" else None,
    description=(
        "Backend for SMARTEVENT: Mobile-Based Inventory, Financial "
        "Management, Event Monitoring, and Data Analytics Reporting "
        "System for Student Organizations (LCUP CITE Department)."
    ),
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
    expose_headers=["Content-Disposition"],
)


app.state.auth_rate_limits = {}
app.add_middleware(RequestSecurityMiddleware, auth_rate_limits=app.state.auth_rate_limits)


@app.exception_handler(RequestValidationError)
async def validation_error(request, exc):
    errors = [{key: error[key] for key in ("loc", "msg", "type")} for error in exc.errors()]
    return JSONResponse({"detail": errors}, status_code=422)


@app.exception_handler(SQLAlchemyError)
async def database_error(request, exc):
    if isinstance(exc, IntegrityError):
        return JSONResponse({"detail": "The change conflicts with existing records"}, status_code=409)
    original = getattr(exc, "orig", None)
    sqlstate = getattr(original, "pgcode", None) or getattr(original, "sqlstate", None)
    if not isinstance(sqlstate, str) or len(sqlstate) != 5 or not sqlstate.isascii() or not sqlstate.isalnum():
        sqlstate = "unknown"
    hint = " Apply pending database migrations." if sqlstate in {"42703", "42P01"} else ""
    logger.error("Database request failed: %s (SQLSTATE %s).%s", type(exc).__name__, sqlstate, hint)
    return JSONResponse({"detail": "The database is temporarily unavailable"}, status_code=503)


app.include_router(auth.router)
app.include_router(notifications.router)
app.include_router(sap.public_router)

for protected_router in (
    sap.router, categories.router, events.router, compliance.router, closure.router, expenses.router, inventory.router,
    incomes.router, analytics.router, reports.router, recommendations.router,
    cite_members.router, departments.router, proposal_letters.router, users.router,
    organizations.router, audit_logs.router, exports.router, receipts.router, files.router,
):
    app.include_router(protected_router, dependencies=[Depends(enforce_read_only)])


@app.get("/health", tags=["health"])
def health_check():
    return {"status": "ok"}
