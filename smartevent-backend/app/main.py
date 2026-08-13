"""
App entrypoint. Run locally with:

    uvicorn app.main:app --reload

Then open http://127.0.0.1:8000/docs for the interactive API docs —
that's the fastest way to test /auth/register and /auth/login by hand
before wiring up Flutter.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import auth

app = FastAPI(
    title="SMARTEVENT API",
    description=(
        "Backend for SMARTEVENT: Mobile-Based Inventory, Financial "
        "Management, Event Monitoring, and Data Analytics Reporting "
        "System for Student Organizations (LCUP CITE Department)."
    ),
    version="0.1.0",
)

# Wide-open CORS for development so the Flutter app (running on an
# emulator/device with a different origin) can hit the API. Tighten
# this to your actual deployed origins before you ship.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)


@app.get("/health", tags=["health"])
def health_check():
    return {"status": "ok"}
