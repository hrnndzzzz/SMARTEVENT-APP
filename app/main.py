"""
App entrypoint. Run locally with:

    uvicorn app.main:app --reload

Then open http://127.0.0.1:8000/docs for the interactive API docs —
that's the fastest way to test /auth/register and /auth/login by hand
before wiring up Flutter.
"""

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.dependencies import enforce_read_only
from app.routers import (
    analytics,
    audit_logs,
    auth,
    categories,
    cite_members,
    departments,
    events,
    exports,
    expenses,
    inventory,
    incomes,
    organizations,
    notifications,
    proposal_letters,
    recommendations,
    reports,
    receipts,
    users,
)

app = FastAPI(
    title="SMARTEVENT API",
    description=(
        "Backend for SMARTEVENT: Mobile-Based Inventory, Financial "
        "Management, Event Monitoring, and Data Analytics Reporting "
        "System for Student Organizations (LCUP CITE Department)."
    ),
    version="0.1.0",
)

# Origins come from ALLOWED_ORIGINS in .env (comma-separated), defaulting
# to "*" so local dev keeps working with no extra setup. Set it to your
# real deployed origin(s) before shipping anywhere public — see
# settings.cors_origins_list / config.py for the parsing logic.
#
# Note: allow_credentials=True + allow_origins=["*"] is technically
# contradictory per the CORS spec (browsers won't actually send
# credentials to a wildcard origin) — this only matters once
# ALLOWED_ORIGINS is set to real origins for a deployed frontend that
# needs cookies/auth headers to survive the CORS check; the JWT
# Authorization header used everywhere in this app isn't a "credential"
# in the CORS sense, so this hasn't caused problems, but it's the first
# thing to check if a deployed frontend reports CORS credential errors.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition"],
)


app.include_router(auth.router)
app.include_router(notifications.router)

for protected_router in (
    categories.router, events.router, expenses.router, inventory.router,
    incomes.router, analytics.router, reports.router, recommendations.router,
    cite_members.router, departments.router, proposal_letters.router, users.router,
    organizations.router, audit_logs.router, exports.router, receipts.router,
):
    app.include_router(protected_router, dependencies=[Depends(enforce_read_only)])


@app.get("/health", tags=["health"])
def health_check():
    return {"status": "ok"}
