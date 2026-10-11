# SMARTEVENT Backend API

Backend for SMARTEVENT: a mobile-based inventory, financial management, event
monitoring and analytics reporting system for student organizations
(LCUP CITE Department capstone project).

The API implements organization-scoped access, roster-based registration,
independent reviews, receipts/OCR, financial reporting and event-linked inventory.
Flutter UI implementation is separate: having an endpoint in Swagger does not
mean its Create/Edit/Delete or other action is already available in the app.

## Documentation

| Document | Purpose |
|---|---|
| [Frontend README](FRONTEND_README.md) | Screens, buttons, forms, permissions and acceptance tests covering all 89 currently registered API operations. |
| [Roles and permissions](ROLES_AND_PERMISSIONS.md) | Hierarchy, scope, officer read-only policy and account administration. |
| [Core features](CORE_SYSTEM_FEATURES.md) | Registration, notifications, academic metadata and exports. |
| [Financial management](FINANCIAL_MANAGEMENT.md) | Fund sources, receipt duplication/review, reports and historical import. |
| [Inventory management](INVENTORY_MANAGEMENT.md) | Event links, typed movements, purchase completion and legacy repairs. |
| [Setup notes](SETUP.md) | Additional environment examples. Current policies here and in the handoffs override older workflow examples. |

Use the deployed /docs and /openapi.json for exact request/response contracts.
Implementation does not certify live migration, external-service or frontend readiness.

## Stack and structure

| Component | Implementation |
|---|---|
| API | FastAPI + Uvicorn |
| Persistence | SQLAlchemy + Supabase PostgreSQL |
| Authentication | Application JWT, OAuth2 password-form login, Argon2 |
| Configuration | pydantic-settings and environment variables / .env |
| Email | Resend for OTP, initial setup, recovery and confirmation |
| Storage | Supabase Storage for receipt images and proposal letters |
| OCR | Gemini image/text parsing and Pillow image processing |
| Reports | JSON, ReportLab PDF, CSV and print-ready HTML |
| Tests | pytest, FastAPI TestClient and isolated SQLite fixtures |

~~~text
app/
  main.py             Router registration, CORS and app entrypoint
  config.py           Environment settings
  database.py         Engine and database sessions
  models.py           ORM models
  schemas.py          Request/response contracts
  security.py         JWT and password hashing
  dependencies.py     Account readiness, role, ownership and scope checks
  rbac_policy.py      Public role descriptions
  routers/            Auth, administration, operations and reports
  services/           Email/OTP, notifications, audit, academic years,
                      storage/OCR, receipts, purchases and report rendering
  test_*.py           Authorization and workflow regression tests
scripts/
  001_...sql through 007_...sql   Database migrations
  create_super_admin.py          Institutional account bootstrap
  deliver_notifications.py       Confirmation-email retry worker
  backfill_receipts.py           Historical receipt import
~~~

Starting the API does not create/migrate tables. Keep PostgreSQL schema,
constraints and triggers aligned with models and migration scripts.

## Local setup

Run from smartevent-backend, using Python 3.11+ and access to the intended database.

~~~powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
# EmailStr validation and the test runner must also be installed.
.\.venv\Scripts\python.exe -m pip install email-validator pytest
~~~

On macOS/Linux use .venv/bin/python. Create a private .env next to app/:

~~~dotenv
# Required at startup
DATABASE_URL=postgresql://<user>:<password>@<host>:<port>/<database>
JWT_SECRET_KEY=<long-private-signing-secret>
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=1440

# Configure actual frontend origins; wildcard is the local default
ALLOWED_ORIGINS=http://localhost:3000

SUPABASE_URL=https://<project>.supabase.co
SUPABASE_SERVICE_KEY=<server-only-service-key>
SUPABASE_RECEIPTS_BUCKET=receipts
SUPABASE_PROPOSAL_LETTERS_BUCKET=proposal-letters

GEMINI_API_KEY=<server-only-api-key>
# GEMINI_MODEL can override the default in app/config.py

RESEND_API_KEY=<server-only-api-key>
RESEND_FROM_EMAIL="SMARTEVENT <noreply@your-verified-domain.example>"
OTP_EXPIRY_MINUTES=15
# RESEND_TEST_EMAIL is for the restricted development-sender setup
~~~

Never commit real secrets or include database/service-role/email/OCR/JWT signing
keys in Flutter. Only DATABASE_URL and JWT_SECRET_KEY are mandatory at startup;
unconfigured storage/OCR/email features return service errors. Legacy Gmail
variables are accepted for compatibility but are not used by the email service.

~~~powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
~~~

- Health: http://127.0.0.1:8000/health
- Swagger: http://127.0.0.1:8000/docs
- API schema: http://127.0.0.1:8000/openapi.json

Devices/emulators need a reachable server address, not their own localhost.
Use HTTPS and explicit allowed web origins in deployment. CORS exposes
Content-Disposition for report filenames.

## Database rollout and bootstrap

Back up the intended database first. Inspect scripts and apply only unapplied
migrations in order. Do not blindly rerun production SQL. The existing base
schema and budget-deduction triggers must be present.

| Migration | Coverage |
|---|---|
| 001_department_scope_and_auth.sql | Department-scoped records and authentication support. |
| 002_otp_registration_purpose.sql | Registration OTP purpose. |
| 003_financial_income_and_dates.sql | Event income and financial dates. |
| 004_roles_and_organizations.sql | Organization ownership, suspension, role rules and audit. |
| 005_core_system_features.sql | Notification inbox and academic-metadata checks. |
| 006_financial_management.sql | Receipts, duplicate controls, financial/linkage constraints. |
| 007_inventory_management.sql | Typed event-linked stock, purchase evidence and provenance guards. |

Some constraints use NOT VALID to preserve historical rows while checking new
inserts/updates. Review actual ownership, academic labels, event links, receipts
and stock, then follow the handoffs' repairs/validation. Never invent historical
years, payments, suppliers or quantities to satisfy a constraint.

The institution appoints the Super Admin. Bootstrap on an authorized maintenance
machine with database and email configured:

~~~powershell
.\.venv\Scripts\python.exe -m scripts.create_super_admin
~~~

This creates an account and sends a temporary password: it is not a read-only
test. There is no public Create Super Admin API.

1. Super Admin logs in and changes the temporary password.
2. Super Admin creates departments/organizations and Admin/SDS accounts.
3. Organization Admin adds approved Adviser/Treasurer/Officer roster entries.
4. Members register with roster email and chosen password, then verify OTP.
5. Eligible verified members activate automatically; role/name/scope come from
   the roster, not a self-selected elevated role.

## Roles and authentication

| Role | Access |
|---|---|
| super_admin | Global operations, department/organization/Admin/SDS provisioning, transfers, account access and audit. |
| admin | Assigned organization/department administration, roster/member access, categories/catalog, finances and independent review. |
| adviser | Scoped reading, own event proposals, independent event/expense/receipt review, movements and letters. |
| treasurer | Scoped reading, own proposals, income/expenses, own pending-expense receipts, purchase completion, movements and letters. |
| officer | Scoped operational read-only access, reports and exports; own password changes and notification read actions remain allowed. |
| sds_staff | School-wide proposal-letter reading and personal account/inbox; no operational events, finances, inventory or reports. |

Sharing a department does not grant cross-organization access. Account transfers
do not transfer historical records. Suspension blocks existing tokens on
subsequent requests; restoration does not bypass verification/password setup.

POST /auth/login takes application/x-www-form-urlencoded fields username
(email) and password, not JSON. Protected calls use Authorization: Bearer
<access_token>. Load GET /auth/me after login and route mandatory-password users
to setup; GET /auth/permissions describes duties. There is no refresh-token
or server-side logout endpoint.

No reviewer, including Super Admin, may approve/reject their own event, expense
or pending receipt review. Role, scope, ownership and state checks are enforced
by the API, not just hidden frontend buttons.

## Current features and workflows

### Registration and notifications

Roster-restricted registration, OTP verification/resend, initial setup, password
change and recovery/reset are implemented. Successful verification creates a
personal notification and attempts a separate confirmation email. Confirmation
email failure does not undo account activation.

Inbox supports unread filtering, limit/offset, unread count and individual
mark-read. Schedule retries in the intended environment:

~~~powershell
.\.venv\Scripts\python.exe -m scripts.deliver_notifications --limit 100
~~~

This sends real emails. Device push and event-review notifications are not implemented.

### Categories

Scoped list/detail plus Admin/Super Admin Create/Edit/Delete. Categories record
allocation and low-balance thresholds. Remaining budget is read-only and deducted
by expense-approval database workflow. Allocation editing does not automatically
top up/recalculate remaining budget. Referenced categories cannot be deleted.

The frontend must expose category CRUD, not just a dropdown.

### Events: two-stage approval

Treasurer/Adviser/Admin/Super Admin can propose events; Officers cannot.
New events require consecutive school year (e.g. 2026-2027), semester
(1st, 2nd, summer) and scope (departmental, organizational). Year filtering/
lookup and administrator legacy-metadata repair exist. Metadata cannot be cleared.

~~~text
Treasurer/Admin/Super Admin: draft -> pending_adviser -> pending_admin -> approved
Adviser:                   draft -> pending_admin -> approved
Pending stage -> rejected -> edit -> resubmit (history retained)
~~~

Legacy pending means awaiting adviser review. Adviser approves the first stage;
Admin/Super Admin approves the final stage and may independently reject either
pending stage. Resubmission uses the original proposer's role. No proposal is
auto-approved: Admin proposals need an independent adviser and another
Admin/Super Admin for final approval.

Owner/scoped administrator can edit drafts/rejected events, submit/resubmit and
delete drafts subject to references. Dedicated actions change status, not generic
PATCH. Approval history exists. Completed is accepted in responses but has no
transition endpoint.

### Expenses, receipts and OCR

Treasurer/Admin/Super Admin create pending expenses with asset/consumable lines.
Owners/administrators edit/delete eligible pending records. Independent
Adviser/Admin/Super Admin approves/rejects in a SINGLE review step, unlike events.
Approval checks category and linked event budgets; database triggers deduct them.

Image scanning before creation, uploading images to existing expenses and parsing
on-device OCR text are implemented. Scan returns an uploaded preview, not a saved
expense: review it and separately Create Expense. OCR discrepancy flags are visible.

Every receipt requires purpose, event and exactly one expense/income link.
Canonical URL, uploaded-file hash and normalized merchant/reference duplicates
are blocked within the organization. Similar merchant/amount/nearby-date receipts
require independent Clear/Reject review with a reason. Receipt-bearing expenses
cannot change event/amount/date, detach evidence or be deleted. Asset approval
requires a registered receipt.

### Income, reports and dashboard

Income records actual source, purpose, received date and positive amount.
Types: registration_fees, sponsorship, donation, other. Create/list and event
filtering exist; income Edit/Delete do not. Pending/rejected receipt review
withholds income from totals.

Category/event/consolidated reports include relevant budgets, eligible income,
approved expenses, balance, actual fund-source breakdowns and withheld income.
Event reports also show transactions and receipts.

- Weekly/monthly: transaction dates and optional reference date.
- School year: school_year required.
- Semester: school_year and semester required.
- Event scope: departmental/organizational filtering.
- Academic reports: actual event labels, not guessed creation years.

Live dashboard, approved-spending trends, flagged-expense queue and historical
category-based budget suggestions exist. Trends group by expense creation month;
calendar reports use transaction dates, so their buckets can differ.

Authenticated dashboard/category/event/financial exports support PDF, CSV and
HTML. GET /analytics/dashboard/exports exposes formats/templates. Fetch with
Bearer authorization, then save/share/print locally; never put JWTs in URLs.
Printing/download controls belong to the frontend team.

### Inventory and completed purchases

New catalog items require an initial/intended event; every movement also requires
its actual event, type and reason. Admin/Super Admin manages catalog CRUD/drafts.
Adviser/Treasurer/Admin/Super Admin records authorized acquisition, donation,
issue, return, disposal and adjustment.

Stock is whole-unit and cannot become negative; returns cannot exceed outstanding
issue for that event. Quantity PATCH and manual purchase movements are blocked.
Deletion requires zero stock and no ledger/purchase history.

~~~text
Event-linked asset expense + receipt -> independent expense approval
-> record full payment and actual delivery through complete-purchase
-> asset stock and purchase ledger added once
-> Admin confirms newly created catalog drafts before manual use
~~~

POST /expenses/{expense_id}/complete-purchase requires approved expense,
matching cleared receipt/full payment, payment/delivery dates, payment method/
reference, vendor and quantity/unit confirmation for every asset line.
Approval alone adds no stock. Repeat completion is blocked; draft confirmation
does not add stock again. Consumables are financial lines, not automatic stock.

Low-stock/draft/event/missing-link views, ledger history and administrator legacy
event/movement repairs exist without replaying quantities. Backend transactions
update stock; migration 007 guards validate provenance, not a second increment.

### Proposal letters, administration and audit

Authorized operational writers upload event-linked PDF/images. Their organization
can read letters; SDS/Super Admin have school-wide visibility. Officers have no
letter access; SDS cannot approve events.

Super Admin provisions departments/organizations/Admin/SDS and transfers accounts.
Organization Admin manages roster/member roles, positions and suspension.
Claimed roster entries are managed through user access, not unclaimed-entry
editing/deletion. Administrative audit history is read-only and scoped.

## API areas

| Prefix | Functionality |
|---|---|
| /auth, /notifications | Registration, login, self-service, role metadata and inbox. |
| /departments, /organizations, /users, /cite-members, /audit-logs | Setup, member access and audit. |
| /categories, /events, /proposal-letters | Categories, proposals/review and documents. |
| /expenses, /incomes, /receipts | Finances, OCR/uploads, evidence review and purchases. |
| /inventory | Catalog, stock ledger, drafts and legacy repair. |
| /analytics, /recommendations, /reports | Dashboard, trends/flags, suggestions and reports/exports. |
| /health | Connectivity only, not database/external-service readiness. |

See [FRONTEND_README.md](FRONTEND_README.md) for complete operation-to-UI mappings,
forms, filters and app acceptance tests.

## Testing and release

~~~powershell
.\.venv\Scripts\python.exe -m pytest app -q -p no:cacheprovider
~~~

The last verified code baseline passed **200 backend tests**. Isolated SQLite
tests do not prove PostgreSQL migrations/triggers, real email/storage/OCR delivery
or frontend completion. Dependency deprecation warnings remain.

Before release:

1. Verify backup, base schema, unapplied migrations, budget triggers, historical
   ownership/metadata/evidence/stock repairs and deferred constraint validation.
2. Verify email sender, storage buckets/privacy, OCR credentials, web origins,
   HTTPS and server-only secrets in the real environment.
3. Test all six roles, organization isolation, suspension, password setup and
   blocked self-review.
4. Exercise live reviews, receipts, complete purchases, movements, income,
   reports and authenticated downloads in a test deployment.
5. Finish frontend acceptance tests, including visible Category Create/Edit/Delete.
6. Configure/monitor notification retries and reviewed historical reconciliation.

## Known boundaries and remaining enhancements

Implemented backend features are not a claim of complete production readiness:

- No income Edit/Delete, saved expense-line editing or rejected-expense resubmit.
- No event-completion transition or arbitrary submitted-history editing.
- No letter Edit/Delete, Delete User or department/organization Edit/Delete APIs.
- No standalone file-only income-receipt creation; metadata creation needs an
  existing HTTP(S) evidence URL before receipt-ID upload.
- Receipt deduplication does not cover every transaction entered without receipts.
- Returned file URLs do not imply private signed-URL protection; review storage
  privacy and extend access controls if institution policy requires it.
- Consumable stock integration, event-review push, generalized notification actions
  and refresh-token/session revocation flows are absent.
- Generic list pagination/search, reviewer names and additional bulk exports
  need agreed backend extensions where not already supported.
- Allocation editing is not a dedicated budget-adjustment/rebalancing operation.

Do not simulate unsupported writes in local state or bypass API restrictions
through direct database writes. Agree extensions and keep contracts synchronized.
