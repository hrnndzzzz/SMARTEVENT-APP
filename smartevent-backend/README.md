# SMARTEVENT — Backend API

Backend for **SMARTEVENT**: a Mobile-Based Inventory, Financial Management,
Event Monitoring, and Data Analytics Reporting System for Student
Organizations (LCUP CITE Department capstone project).

This README is a handoff document — it covers what's built, how it's
structured, the design decisions behind it, and what's left to do.

---

## 1. Stack

| Layer            | Choice                                      |
|-------------------|----------------------------------------------|
| Framework         | FastAPI                                      |
| ORM               | SQLAlchemy                                   |
| Database          | Supabase Postgres                            |
| Auth              | JWT (`python-jose`), OAuth2 password flow    |
| Password hashing  | Argon2 (`pwdlib`)                            |
| Settings          | `pydantic-settings`, reads `.env`            |
| Dev server        | `uvicorn`                                    |

No frontend code lives here — this is the API only. The Flutter app is a
separate repo/codebase and consumes this over HTTP.

---

## 2. Project structure

```
app/
├── main.py           # FastAPI app instance, CORS, router registration
├── config.py          # Settings — reads DATABASE_URL, JWT secret, etc. from .env
├── database.py        # SQLAlchemy engine/session, get_db() dependency
├── models.py           # ORM models (mirrors the Supabase schema — does NOT create tables)
├── schemas.py          # Pydantic request/response schemas
├── security.py         # Password hashing + JWT encode/decode
├── dependencies.py     # get_current_user, require_role(...)
└── routers/
    ├── auth.py         # register / login / me
    ├── categories.py   # budget category CRUD
    ├── events.py        # event proposals + approval workflow
    ├── expenses.py       # expense records + approval workflow + budget check
    └── inventory.py       # item CRUD + stock transactions
```

**`models.py` does not create tables.** The Supabase SQL schema (triggers,
Row Level Security, indexes, seed data) is the source of truth. The ORM
classes just let FastAPI query what's already there. If you need to change
a column, change it in Supabase first, then update `models.py` to match —
not the other way around.

---

## 3. Running it locally

```bash
uvicorn app.main:app --reload
```

Then open `http://127.0.0.1:8000/docs` for interactive Swagger docs — the
fastest way to test any endpoint by hand.

### Required `.env` variables (see `config.py`)

```
DATABASE_URL=postgresql://...          # Supabase pooled connection string
JWT_SECRET_KEY=...                     # any long random string
JWT_ALGORITHM=HS256                    # default, usually leave as-is
JWT_EXPIRE_MINUTES=1440                # default 24h

# Not wired up to any route yet — reserved for the receipt-upload phase
SUPABASE_URL=
SUPABASE_SERVICE_KEY=
SUPABASE_RECEIPTS_BUCKET=receipts
```

---

## 4. Auth model

- Three roles: `admin`, `adviser`, `officer` (see `Role` in `schemas.py`).
- `POST /auth/register` is currently **open to anyone** — no auth required.
  This is intentional for now (it's how you create your first admin
  account), but it should be locked down before real deployment — e.g.
  restrict it to admins only via `Depends(require_role("admin"))`, or add
  a "pending approval" state for new accounts.
- All protected routes take a `Bearer <token>` header. In Swagger, use the
  **Authorize** button after logging in — see the two role-based
  dependencies below.
- `dependencies.py` has two building blocks used everywhere:
  - `get_current_user` — validates the token, loads the `User` row.
  - `require_role("admin")` / `require_role("adviser", "admin")` — wraps
    `get_current_user` with a role check, used to gate admin-only or
    reviewer-only routes.

---

## 5. Router-by-router summary

### `auth.py`
`POST /auth/register`, `POST /auth/login`, `GET /auth/me`. Standard OAuth2
password flow. Login takes `username` (mapped to email) + `password` as
form data, not JSON — that's the OAuth2 spec shape, not a bug.

### `categories.py`
Budget category CRUD (`POST`, `GET` list/single, `PATCH`, `DELETE`).
- View: anyone logged in.
- Create/update/delete: admin only.
- `remaining_budget` is **never** editable through this router — it only
  changes via a Supabase trigger (`fn_deduct_category_balance`) that fires
  when an expense's status flips to `approved`.
- Delete is blocked (409) if any event or expense still references the
  category, to avoid orphaned foreign keys.

### `events.py`
Event proposal CRUD + approval workflow.

```
draft --submit--> pending --approve--> approved
                       \--reject--> rejected
```

- View: anyone logged in.
- Create: any logged-in user (in practice, officers).
- Edit/submit/delete: only the user who proposed it (or an admin), and
  only while status is `draft`.
- Approve/reject: `adviser` or `admin` only, only while status is
  `pending`. Every decision writes a row to the shared `approvals` table
  (`entity_type="event"`), so `GET /events/{id}/approvals` gives a full
  review timeline, not just the final status.
- `status` is deliberately **excluded** from the `PATCH` body — status
  only moves through `/submit`, `/approve`, `/reject`.
- `completed` exists as a valid status value but **has no route yet** —
  nothing currently transitions an approved event to completed. Add a
  `POST /events/{id}/complete` when that need comes up.

### `expenses.py`
Expense record CRUD + approval workflow. Same shape as events, reusing the
same `approvals` table (`entity_type="expense"`).

- No `draft` state — an expense is filed once money's actually been
  spent, so it starts at `pending`.
- **Budget guard on approval**: before approving, the router checks
  `expense.amount` against `category.remaining_budget` and returns a 409
  if approving would overdraw the category. This is an API-level check
  *in addition to* the DB trigger — the trigger still does the actual
  deduction once approval goes through.
- `category_id` is validated against the `categories` table on create/edit
  with a clean 400 if it doesn't exist, rather than letting a bad UUID
  surface as an ugly 500 foreign-key error.
- OCR fields (`ocr_merchant`, `ocr_date`, `ocr_amount`) and
  `is_flagged`/`flag_reason` are read-only through this API for now —
  they're meant to be populated by an OCR pipeline that doesn't exist yet
  (see Phase 3 below).

### `inventory.py`
Item CRUD + stock transaction log.

- View: anyone logged in. Create/update/delete: admin only.
- `GET /inventory/low-stock` — items where `quantity <= low_stock_threshold`.
  **Route ordering matters here**: it's declared before
  `GET /inventory/{inventory_id}`, otherwise FastAPI tries to parse
  `low-stock` as a UUID and throws a 422.
- `quantity` is **not editable via PATCH** — it only changes through
  `POST /inventory/{id}/transactions`, so every quantity change has a
  matching `InventoryTransaction` row explaining why.
- **No DB trigger for inventory** (unlike categories' budget trigger) —
  this router updates `Inventory.quantity` directly in the same commit as
  the transaction insert. If a trigger gets added later in Supabase,
  remove the manual `item.quantity = new_quantity` line in
  `create_transaction` to avoid double-counting.
- Negative stock is blocked with a 409 (can't check out more than what's
  on hand).
- `quantity` / `low_stock_threshold` are typed `int` at the API layer
  (whole-unit items — chairs, cords, tarps). The underlying Supabase
  columns are `Numeric`, so this is a validation choice, not a DB change.

---

## 6. Design patterns used throughout (worth knowing before extending)

- **Status transitions never go through `PATCH`.** Every status-changing
  action (`submit`, `approve`, `reject`) is its own POST route. This keeps
  side effects (trigger firing, approval logging) tied to one code path
  each, instead of being reachable through a generic edit.
- **Trigger-owned fields are excluded from update schemas.**
  `remaining_budget` and `quantity` are never in a `*Update` schema — only
  the dedicated action routes touch them.
- **Ownership checks follow the same shape**: `_assert_owner_or_admin` in
  `events.py` / `expenses.py` — the creator or an admin can edit/delete
  while the record is still editable (`draft` / `pending`).
- **Shared `approvals` table, disambiguated by `entity_type`.** Both
  events and expenses log to the same table, filtered by
  `entity_type="event"` / `"expense"` and `entity_id`. `step_order`
  auto-increments per entity.
- **Delete is blocked, not cascaded**, whenever a record is referenced
  elsewhere (categories referenced by events/expenses, inventory items
  referenced by transactions). Client gets a 409 with a suggested
  alternative (e.g. zero out the budget instead of deleting the category).

---

## 7. Known gaps / things to fix before production

- `POST /auth/register` is wide open — lock it down (admin-only, or an
  approval step for new accounts).
- CORS in `main.py` is `allow_origins=["*"]` — fine for local dev with the
  Flutter emulator, **must** be tightened to real deployed origins before
  shipping.
- No self-review lock: an adviser can currently approve/reject an event or
  expense they proposed/filed themselves. Add a check comparing
  `reviewer.id` to `proposed_by` / `recorded_by` if segregation of duties
  matters for your org's policy.
- `Event.status = "completed"` has no route that sets it.
- Receipt upload isn't wired to Supabase Storage yet — `receipt_url` on
  `ExpenseCreate` just accepts a plain string for now.

---

## 8. Roadmap — what's next

**Phase 1 — Foundation** ✅ Done
Supabase schema, FastAPI scaffold, DB connection.

**Phase 2 — Core CRUD + Approval Routers** ✅ Done
Auth, Categories, Events, Expenses, Inventory — all built and manually
tested end-to-end (create → edit → status transitions → approvals →
guards for invalid transitions).

**Phase 3 — Receipts, OCR & Notifications** 🔜 Not started
- Wire `receipt_url` to actual Supabase Storage uploads
  (`supabase_url` / `supabase_receipts_bucket` are already stubbed in
  `config.py`).
- OCR pipeline to auto-populate `ocr_merchant`, `ocr_date`, `ocr_amount`
  on an expense, and set `is_flagged` / `flag_reason` when OCR results
  don't match what was typed in.
- Push notifications via `User.fcm_token` (e.g. notify an officer when
  their event/expense is approved or rejected).

**Phase 4 — Analytics & Reporting**
Dashboards / reports pulling from `AuditLog`, category spend history,
event outcomes — the "Data Analytics Reporting System" part of the
project's full title. No router exists for this yet.

**Phase 5 — Flutter Integration + Deployment**
Wiring the mobile app to these endpoints, end-to-end testing, and
deployment hardening (see gaps above — CORS, open registration, etc.).

---

## 9. Quick sanity checklist for a new developer

1. `uvicorn app.main:app --reload`, confirm `/health` returns `{"status": "ok"}`.
2. Open `/docs`, confirm all 5 route groups appear: `auth`, `categories`,
   `events`, `expenses`, `inventory`.
3. Register one account per role (`admin`, `adviser`, `officer`) via
   `POST /auth/register`, log each in, and use the **Authorize** button in
   Swagger to test as each role.
4. Walk one full loop manually: create a category → create an event
   against it → submit → approve → create an expense against the same
   category → approve it → confirm `remaining_budget` drops correctly.
5. Do the same for inventory: create an item → record a stock-out
   transaction → confirm `quantity` drops and shows up in
   `/inventory/{id}/transactions` → try over-withdrawing and confirm the
   409.
