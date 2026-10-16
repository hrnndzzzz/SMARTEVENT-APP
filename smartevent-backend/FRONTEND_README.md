# SMARTEVENT frontend implementation checklist

This is the Flutter/frontend team's screen-and-action handoff, checked against
the registered FastAPI routes at backend commit `44b0b70` (27 September 2026).
It describes what must be reachable in the app, not just what works in Swagger.
It does **not** certify that the current Flutter screens implement these actions.

**Completion rule:** every supported user action below needs a visible entry
point, working API call, permission/state checks, loading/error/success feedback,
and a refreshed screen. A list-only screen is not complete when that module
also supports Create, Edit, Delete, Review, Upload, or another action.


This document and the four feature handoffs supersede older workflow/roadmap
examples in the main README. The deployed `/openapi.json` and `/docs`, request
schemas, and route checks are the exact API contract when backend versions change.

## 1. Shared integration rules

- Configure the API base URL per environment; do not hardcode localhost in builds.
  The emulator/device must be able to reach that backend address.
- All protected requests use `Authorization: Bearer <access_token>` over HTTPS
  outside local development. Do not put tokens in URLs, logs, or report links.
- Use backend authentication; do not substitute Supabase Auth tokens or direct
  table writes. Never put database passwords, service-role keys, Resend keys,
  Gemini keys, or JWT signing secrets in the app.
- Login sends form data, NOT JSON: `username=<email>&password=<password>` with
  `application/x-www-form-urlencoded`. Most other writes send JSON. Uploads
  send multipart form data with the field names below.
- After login, load `/auth/me`. Route initial-password users to password setup
  before operational screens. Load `/auth/permissions` for role explanations;
  it is descriptive metadata, not a per-record `canEdit`/`canDelete` API.
- Implement role + scope + ownership + record-state checks together. Hiding a
  button is UX, not security; the API remains the authority and can reject it.
- PATCH sends only changed fields. Do not serialize the whole response object
  back into PATCH, or send null for omitted values. Some nullable response fields
  are legacy compatibility, NOT permission to create incomplete new records.
- Preserve UUIDs as strings. Send dates as `YYYY-MM-DD`; parse timezone-aware
  timestamps and display in the intended local timezone.
- Money inputs must use decimal-safe handling, positive values and at most two
  decimal places for income/expenses/receipts/payment. Budget fields allow zero.
  Do not calculate authoritative balances or stock by floating-point arithmetic.
- Use real API data, not sample dashboard totals. Support loading, empty,
  retryable error, and success states on every screen; preserve unsaved forms.
- Most list routes return plain arrays with no generic search/pagination API.
  Apply local search/status filters to loaded data where necessary and label
  them accordingly. Only send supported query parameters listed below.
- Disable repeated submits while a request is in flight. Financial writes do
  not have a general idempotency-key contract: after a timeout, check the list
  before retrying blindly. Purchase completion specifically blocks double stock.
- On logout, clear credentials and user-scoped cached data. There is no logout
  endpoint or refresh-token endpoint. Reauthenticate after JWT expiry.
- Refresh affected lists/details/dashboard/reports after successful actions.
  Treat DELETE `204` as success without trying to parse a JSON body.

### Required error handling

| Response | UI handling |
|---|---|
| 400 | Display invalid selection, duplicate name, file, or other backend explanation. |
| 401 | Wrong credentials/password or expired/invalid token; distinguish login errors from session expiry. |
| 403 | Explain role, scope, ownership, suspension, or password-setup restriction. Do not bypass it. |
| 404 | Record no longer available; refresh the list and exit stale detail if appropriate. |
| 409 | Explain workflow conflict: in-use category, self-review restriction where applicable, receipt duplicate, budget limit, draft/stock/history restriction, already-completed purchase, etc. |
| 422 | Map `detail` validation entries to fields; `detail` can also be a plain string. |
| 502 / 503 | Storage, OCR, or email/service unavailable; preserve input and offer a safe retry. |
| Network/5xx | Do not show false success or silently retry financial writes. |

Render API messages as text, not executable HTML. Password/OTP values must never
be included in diagnostic logs or analytics.

## 2. Navigation and roles

| Role | Required navigation | Write controls |
|---|---|---|
| `super_admin` | Dashboard, Categories, Events, Expenses, Income, Receipts, Inventory, Reports, Proposal Letters, Departments, Organizations, Accounts, Roster, Audit, Notifications, Profile | All supported administrative/operational actions, still subject to states and no self-review. |
| `admin` | Operational modules above plus own organization's Roster, Accounts, Audit, Notifications, Profile | Category/catalog CRUD, member access administration, finance/event actions within assigned organization. No create Admin/SDS, school setup, or transfers. |
| `adviser` | Dashboard, Categories, Events, Expenses, Income, Receipts, Inventory, Reports, Proposal Letters, Notifications, Profile | Own event proposals, independent review, inventory movements, proposal-letter upload. No category/catalog CRUD or finance recording. |
| `treasurer` | Same operational navigation as Adviser | Own event proposals, record income/expenses, own pending-expense editing/receipt actions, own purchase completion, movements, letters. No approval or catalog/category CRUD. |
| `officer` | Dashboard, Categories, Events, Expenses, Income, Receipts, Inventory, Reports, Notifications, Profile | Operational read-only. No Create/Edit/Delete/Submit/Approve/Upload/stock-movement controls. Own password changes and notification mark-read remain allowed. No proposal-letter access. |
| `sds_staff` | Proposal Letters, Notifications, Profile | Read school-wide proposal letters only; no operational dashboard, events, finance, inventory, reports, or administrative screens. |

Organization and department scope are both enforced. Organizations sharing a
department cannot see each other's records. Scope comes from `/auth/me`; do not
offer arbitrary organization selectors to ordinary users. Super Admin has global
access, but some list routes do not provide organization query filters: do not
invent server-side filters. Department/organization lookup endpoints are for
Admin/Super Admin; non-admin operational forms use the account's scope and
already-accessible records instead of calling forbidden lookup endpoints.

Position labels such as President or Secretary do not override the officer's
read-only role. A Treasurer must actually have `role=treasurer`.

## 3. Account, registration and notifications

| UI action | API | Required behavior |
|---|---|---|
| Register | `POST /auth/register` | Email + chosen password (minimum 8 characters). Role/name/scope come from an approved roster entry, not a role picker. Show Verify Email next, not an operational dashboard. |
| Verify registration | `POST /auth/verify-otp` | Email + six-character `otp_code`; show registration approval and confirmation-email status separately. |
| Resend verification | `POST /auth/resend-otp` | Email. Explain invalid/expired OTP without destroying registration progress. |
| Login | `POST /auth/login` | Email in form field `username`, password in `password`; save returned access token securely. |
| Profile/session | `GET /auth/me` | Name, email, role, position, organization/department IDs, activation/suspension and password-setup status. |
| Role explanation | `GET /auth/permissions` | Display the current role's duties/scope; use route rules for actual action gating. |
| Change/setup password | `POST /auth/change-password` | `current_password`, `new_password`; mandatory first-login flow when `must_change_password=true`. |
| Forgot password | `POST /auth/forgot-password` | Email request screen; avoid exposing account enumeration through extra client assumptions. |
| Reset password | `POST /auth/reset-password` | Email, `otp_code`, `new_password`. |
| Notification inbox | `GET /notifications` | `unread_only`, `limit` (1–100), `offset`; show title, body, created time and read state. |
| Unread badge | `GET /notifications/unread-count` | Update the notification badge from the returned count. |
| Mark notification read | `PATCH /notifications/{notification_id}/read` | No JSON payload required; update only the authenticated user's notification. |

Registration is automatically approved ONLY after roster eligibility and OTP
verification pass. There is no separate registration-approval button to build.
Confirmation email failure does not undo successful activation; display
`confirmation_email_status` without falsely telling the user registration failed.
Notifications currently cover registration confirmation; do not promise event
approval push notifications, device push delivery, mark-all-read, or notification
deletion without additional backend work.

## 4. Categories: full CRUD is mandatory

Required screen: category list + detail + create/edit form + delete confirmation.
Show name, allocation, remaining budget and low-balance threshold. Include a
visible **Create Category** button and item-level **Edit**, **Delete**, and
**View Report** controls for the appropriate roles.

| UI action | API | Permission/state |
|---|---|---|
| List | `GET /categories` | Operational readers. |
| View detail | `GET /categories/{category_id}` | Accessible record only. |
| Create Category | `POST /categories` | Admin/Super Admin. Fields: `name`, `allocated_budget`, `low_balance_threshold`; scope IDs as required. |
| Edit Category | `PATCH /categories/{category_id}` | Admin/Super Admin. Edit supported descriptive/allocation/threshold fields; do not use this to transfer scope. |
| Delete Category | `DELETE /categories/{category_id}` | Admin/Super Admin. Blocked with 409 if referenced by any event or expense. |

`remaining_budget` is display-only and deducted by backend/database workflow.
Changing `allocated_budget` is NOT a guarantee that remaining budget is topped
up/recalculated: the current category PATCH simply updates supplied fields.
Do not invent a client-only budget adjustment or archive operation.
If categories are empty, Admin sees a create CTA; other roles see an explanatory
empty state. Test that a UI-created category appears in the event/expense picker.

## 5. Events: proposals, two-stage review and reporting dimensions

Required screen: list/status tabs + create/edit + detail + review dialog + approval
timeline. Detail should link to finances, inventory usage, letters and reports.

| UI action | API | Permission/state |
|---|---|---|
| List/filter | `GET /events` | Query: `school_year`, `missing_school_year`; other status/search filters are local. |
| Year picker | `GET /events/school-years` | Existing accessible years. New event forms must also allow a valid new year. |
| Detail | `GET /events/{event_id}` | Operational readers. |
| Create/save draft or submit immediately | `POST /events` | Treasurer/Adviser/Admin/Super Admin; `status` is `draft` or `pending`, not arbitrary final status. |
| Edit | `PATCH /events/{event_id}` | Original Treasurer/Adviser proposer or scoped Admin/Super Admin; only draft/rejected events. |
| Submit/resubmit | `POST /events/{event_id}/submit` | Same ownership policy; draft/rejected only. |
| Approve current review stage | `POST /events/{event_id}/approve` | Adviser at adviser stage; Admin/Super Admin at admin stage; never original proposer. Optional `remarks`. |
| Reject | `POST /events/{event_id}/reject` | Adviser at adviser stage; Admin/Super Admin at either pending stage; never original proposer. Optional `remarks`. |
| Delete draft | `DELETE /events/{event_id}` | Owner or scoped administrator; draft only. References may still prevent deletion. |
| Approval history | `GET /events/{event_id}/approvals` | Show reviewer ID, decision, remarks, timestamp and step order. |
| Repair legacy academic data | `PATCH /events/{event_id}/academic-metadata` | Admin/Super Admin only; fills missing fields without overwriting existing academic metadata. |

Form fields: `title`, optional `description`, `category_id`, `event_date`,
`estimated_cost`, `allocated_budget`, and required `school_year`, `semester`,
`event_scope`. Scoped users use their assigned scope; Super Admin supplies/selects
the applicable IDs. Departmental events require a department. Category and event
must share organization/department. Display `remaining_budget` as read-only.

Use these exact values:

- School year: consecutive years, e.g. `2026-2027`; `2026-2028` is invalid.
- Semester: `1st`, `2nd`, `summer`.
- Event scope: `departmental`, `organizational`.

```text
Treasurer/Admin/Super Admin proposal:
draft -> pending_adviser -> pending_admin -> approved
Adviser proposal:
draft -> pending_admin -> approved
Either pending stage -> rejected -> edit -> resubmit (history retained)
```

Legacy `pending` means awaiting adviser review. Initial review stage is based
on the original proposer, including resubmission by an administrator. No proposal
is auto-approved. Admin-origin proposals need an independent adviser and another
Admin/Super Admin for final approval. Officers cannot propose events.

Show both pending states separately in lists and dashboard counts. Do not show
Approve to an Admin while an event is waiting for adviser approval. Do not show
Approve/Reject for `proposed_by == current_user.id`. The backend returns reviewer
IDs, not necessarily display names; do not fetch `/users` from unauthorized roles
just to decorate a timeline. Agree a name-display enhancement with the backend if needed.

`completed` is accepted in responses, but there is no Complete Event route.
Do not implement a fake client-only Complete button or PATCH the status.

## 6. Expenses and receipt scanning

Required screen: expense list + detail + create/edit form + itemized lines +
receipt preview + flags + review/history + purchase-completion entry point.

| UI action | API | Permission/state |
|---|---|---|
| List | `GET /expenses` | Operational readers; event/status search is local unless a backend filter is added. |
| View detail | `GET /expenses/{expense_id}` | Accessible expense. |
| Create Expense | `POST /expenses` | Treasurer/Admin/Super Admin. Creates pending expense. |
| View line items | `GET /expenses/{expense_id}/items` | Include classification, amount, quantity, unit, converted inventory ID. |
| Edit Expense | `PATCH /expenses/{expense_id}` | Treasurer's own pending expense or scoped administrator. Items are NOT editable through this PATCH. |
| Delete Expense | `DELETE /expenses/{expense_id}` | Own pending expense or administrator; recorded receipts block deletion. Use review/rejection instead. |
| Approve Expense | `POST /expenses/{expense_id}/approve` | Independent Adviser/Admin/Super Admin, pending only; optional `remarks`. |
| Reject Expense | `POST /expenses/{expense_id}/reject` | Same independent review policy; optional `remarks`. |
| Approval history | `GET /expenses/{expense_id}/approvals` | Timeline of decisions and remarks. |
| Scan receipt before saving | `POST /expenses/scan-receipt` | Finance writers; multipart `file`; inspect/correct returned OCR data before Create Expense. |
| Upload expense receipt | `POST /expenses/{expense_id}/receipt` | Own pending expense or administrator; multipart `file`; returns updated expense. |
| Parse OCR text | `POST /expenses/{expense_id}/parse-receipt` | Own pending expense or administrator; JSON `raw_text` from on-device OCR; returns updated expense. |
| Complete asset purchase | `POST /expenses/{expense_id}/complete-purchase` | Own approved expense or administrator; see section 9. |

Create form: category, event, description/purpose, total amount, expense date,
optional receipt metadata/URL, itemized lines. Each line has `name`, `amount`
(line total, not a unit price to multiply again), `category` (`asset`/`consumable`),
positive whole-unit `quantity`, and `unit`. Line totals cannot exceed the expense
total. Event is nullable in the API, but event receipts and stock purchases need
a real event link; make it mandatory for those flows.

Once a receipt is recorded, event/amount/date cannot be changed, and the receipt
cannot be detached. Approved/rejected expenses are not editable. No rejected-
expense resubmit endpoint exists. Expense approval is a SINGLE review decision,
not the two-stage event workflow. Approval checks both category and event budgets,
and receipt review; asset expense approval requires a recorded receipt.

Scanning uploads a file but does not create an Expense. A returned preview is
NOT saved until the user submits `POST /expenses`. Review merchant/date/total and
asset/consumable classification manually. Display `is_flagged`, `flag_reason`,
`ocr_merchant`, `ocr_date`, and `ocr_amount`; do not hide mismatches.

Receipt image uploads accept JPEG/JPG, PNG, WebP, HEIC, up to 10 MB. Use camera
and gallery pickers, preview/cancel, progress/error feedback and a manual form
fallback if OCR/storage is unavailable. Both OCR routes are supported integration
options; the team can choose one user flow without exposing two confusing scan buttons.

## 7. Income and fund sources

| UI action | API | Permission/state |
|---|---|---|
| Record Income | `POST /incomes` | Treasurer/Admin/Super Admin; no separate approval endpoint. |
| Income ledger/detail selection | `GET /incomes` | Operational readers; optional `event_id` filter. Detail may use the selected list row: no single-income GET exists. |

Required form: `event_id`, `source` (actual payer/source description),
`source_type` (`registration_fees`, `sponsorship`, `donation`, `other`),
`purpose`, positive `amount`, `received_on`; optional nested receipt.
Show source type AND actual source, amount, purpose, date, recorder ID and
`receipt_review_status`. Do not create artificial income from an event's
estimated/allocated budget or expected participant count.

There is no income Edit/Delete API. Do not create nonfunctional buttons or change
financial records only in local state. If corrections are required, log a backend
requirement rather than inventing negative income entries. Income receipt review
`pending`/`rejected` excludes that income from financial totals; show it in the
ledger with a withheld/rejected label.

## 8. Receipts, duplicate detection and independent review

Required screen: receipt list + event/review filters + detail/image preview +
similar-receipt comparison + pending-review queue.

| UI action | API | Permission/state |
|---|---|---|
| Record/update receipt metadata | `POST /receipts` | Treasurer's own transaction or administrator; exactly ONE `expense_id` or `income_id`. Backend upserts the transaction's receipt subject to immutability rules, not generic unrestricted editing. |
| List/filter | `GET /receipts` | `event_id`, `flagged_only`, `review_status` (`clear`, `pending`, `cleared`, `rejected`). |
| Detail/comparison | `GET /receipts/{receipt_id}` | Load accessible IDs from `similar_receipt_ids` for comparison. |
| Upload receipt image | `POST /receipts/{receipt_id}/upload` | Own transaction or administrator; multipart `file`; requires an existing receipt ID. |
| Clear/reject similar receipt | `POST /receipts/{receipt_id}/review` | Independent Adviser/Admin/Super Admin; pending review only; `decision` = `cleared` or `rejected`, `reason` minimum 10 characters. |

Metadata fields: `receipt_url` (HTTP(S)), required nonblank `purpose`, optional
`merchant`, `receipt_number`, `issued_on`, `amount`. Event and transaction scope
are derived from the linked transaction, not free-text event names. Receipt
amount must match the transaction; date/amount can default from it where allowed.

Known exact duplicate URL/file/reference returns 409. Similar merchant + same
amount + nearby date can be saved as pending review. Display both detection
results without presenting them as proven fraud. Pending/rejected expense receipts
block approval/purchase completion. Pending/rejected income receipts withhold totals.
Cleared/rejected review records are immutable; rewriting metadata cannot erase a flag.

For expenses, a practical file-first path is Scan -> review form -> Create Expense
with nested receipt metadata and the returned URL, or create a pending event-linked
expense then upload through its receipt endpoint. For income, the current API has
no standalone create-from-file endpoint: create income/receipt with a real existing
HTTP(S) evidence URL, then optionally upload against that receipt ID. If the team
needs file-only income creation, request a backend extension; never use a fake URL
or misuse an expense scan to bypass this integration gap.

No receipt DELETE or arbitrary PATCH exists. File URLs are currently returned by
storage; opening them is not the same as downloading a protected report. Do not
claim private signed-URL protection if deployment has not implemented it.

## 9. Purchase completion: separate from expense approval

Required button on eligible approved asset expenses: **Complete Purchase / Record
Payment and Delivery**. Hide/disable when already completed or no asset lines;
explain receipt/event/review prerequisites. Load actual line IDs through the items API.

Submit `POST /expenses/{expense_id}/complete-purchase` with:

```json
{
  "paid_on": "2026-09-26",
  "received_on": "2026-09-27",
  "paid_amount": "1200.00",
  "payment_method": "cash",
  "payment_reference": "PAY-2026-001",
  "vendor": "Actual supplier",
  "items": [
    {"expense_item_id": "<actual-asset-line-UUID>", "quantity": 4, "unit": "pcs"}
  ]
}
```

Dates cannot be future dates. Payment methods: `cash`, `bank_transfer`, `card`,
`other`. Full paid amount must equal the expense amount. Include each asset line
exactly once and no consumable/foreign lines. Confirm actual received quantity/unit.

```text
Create expense + event + asset lines + receipt
-> resolve any receipt review -> independent expense approval
-> record full payment and actual delivery -> stock added once
-> Admin confirms any newly created draft catalog item before manual use
```

Approval alone MUST NOT add stock. New catalog records may be `is_draft=true`;
existing catalog items can be reused. Display payment/vendor/date fields and
`purchase_completed_at`; link each `converted_inventory_id` to inventory details.
Refresh expenses, items, inventory and stock ledger after completion. Confirming
a catalog draft does not add stock again. Consumables do not automatically enter
stock through this purchase-completion implementation.

## 10. Inventory: catalog CRUD, movements and legacy repair

Required screen: catalog list/detail + create/edit + delete confirmation +
low-stock/draft tabs + movement form + event-linked ledger.

| UI action | API | Permission/state |
|---|---|---|
| List/filter | `GET /inventory` | `is_draft`, `event_id`, `missing_event`. Event filtering includes primary event or movement usage. |
| Low-stock tab | `GET /inventory/low-stock` | Show quantity, threshold and unit. |
| Detail | `GET /inventory/{inventory_id}` | Operational readers. |
| Create Item | `POST /inventory` | Admin/Super Admin; event-linked catalog plus optional documented opening stock. |
| Edit Item | `PATCH /inventory/{inventory_id}` | Admin/Super Admin; metadata only, never quantity. |
| Delete Item | `DELETE /inventory/{inventory_id}` | Admin/Super Admin; only zero stock with no transaction/purchase provenance. |
| Confirm Draft | `POST /inventory/{inventory_id}/confirm-draft` | Admin/Super Admin; draft with event link only; does not increment quantity. |
| View movement ledger | `GET /inventory/{inventory_id}/transactions` | Optional `event_id`; show signed change, type, reason, performer, time and purchase-line link. |
| Record movement | `POST /inventory/{inventory_id}/transactions` | Treasurer/Adviser/Admin/Super Admin; event-linked, non-draft, usable item. |
| Repair legacy movement metadata | `PATCH /inventory/{inventory_id}/transactions/{transaction_id}/metadata` | Admin/Super Admin; incomplete/legacy records only; cannot replay or change stock quantities. |

Create form: `event_id`, `item_name`, `description`, whole-unit starting
`quantity` >= 0, `unit`, `low_stock_threshold` >= 0, `location`, `reason`,
`initial_transaction_type` (`opening_balance`, `acquisition`, `donation`), scope
as applicable. Do not record newly purchased goods as opening stock to bypass
payment completion. Positive starting stock creates opening ledger history.

Edit form: name, description, location, threshold, permitted unit changes;
`event_id` can repair a missing legacy primary link but not replace an existing
primary link. Unit changes can be blocked when stock/history exists. Stock quantity
is read-only. To use an item at another event, record an event-linked movement,
not a primary-event rewrite.

Movement form: required event, `transaction_type`, signed nonzero integer
`change_qty`, nonblank `reason` (up to 100 characters).

| User-facing operation | Sent type | Quantity sign |
|---|---|---|
| Acquire (non-purchase) | `acquisition` | Positive |
| Donation received | `donation` | Positive |
| Issue/use for event | `issue` | Negative |
| Return from event | `return` | Positive; cannot exceed outstanding issue quantity for that event. |
| Dispose damaged/lost item | `disposal` | Negative |
| Documented adjustment | `adjustment` | Positive or negative, never zero. |
| Purchased items | NOT a manual movement button | Use Complete Purchase on the expense. Direct `purchase` movement returns 409. |

For user clarity, accept a positive count in Issue/Dispose forms and convert it
to a negative `change_qty` deliberately. Never allow negative resulting stock.
Opening balance and legacy classification are not ordinary movement choices.
Repair metadata uses `event_id`, permitted `transaction_type`, `reason`, and does
not touch historical quantity. Keep legacy repair in an administrator-only section.

## 11. Dashboard, analytics, recommendations and reports

| UI action | API | Required presentation |
|---|---|---|
| Dashboard cards | `GET /analytics/dashboard` | Category count, allocated/remaining totals, events/expenses by status, flagged expense count, low stock and draft inventory counts. |
| Spending chart | `GET /analytics/spending-trends` | Optional `months` (default 6); approved-expense monthly trends, not invented/sample values. |
| Flagged expense queue | `GET /analytics/threats` | Flag details with navigation to actual expense/receipt. Do not label every flag as fraud. |
| Budget suggestion | `GET /recommendations/event-budget` | Required `category_id`; show sample size, averages and note. Handle insufficient data/null averages without fabricating a recommendation. |
| Category report | `GET /reports/category/{category_id}` | Category totals/budget data. |
| Event financial report | `GET /reports/event/{event_id}` | Income, approved-spending total, balance, fund sources, receipts, expenses and withheld-income figures. |
| Consolidated report | `GET /reports/financial` | Required `period`, optional filters described below. |
| Existing consolidated PDF | `GET /reports/financial.pdf` | Same period/filter contract; can use generic exports instead for a consistent UI. |
| Export discovery | `GET /analytics/dashboard/exports` | Supported MIME types and relative URL templates; prepend configured API base URL. |
| Dashboard download/print | `GET /reports/dashboard/export` | Query `format=pdf`, `csv`, or `html`. |
| Event download/print | `GET /reports/event/{event_id}/export` | Same format choices. |
| Category download/print | `GET /reports/category/{category_id}/export` | Same format choices. |
| Financial download/print | `GET /reports/financial/export` | Same report filters plus `format`; export MUST match the displayed selection. |

Build financial filter controls for:

- `period=weekly`: reference date selects the Monday–Sunday week.
- `period=monthly`: reference date selects that calendar month.
- `period=school_year`: school year is required.
- `period=semester`: school year AND semester are required.
- Optional `school_year`, `semester`, `event_scope` further narrow the report;
  event scope selector has All / Departmental / Organizational.

Calendar reports filter actual income received dates and expense dates, not event
dates. Academic reports use event school-year/semester labels. Show the returned
date window/filter labels. Unassigned historical expenses may contribute to
unfiltered calendar totals, not filtered academic/event totals. Do not force
report totals to equal a naive sum of currently displayed event cards.
The current spending-trend chart groups expenses by `created_at`, not
`expense_date`; label it accordingly and do not assume its monthly buckets
always match date-filtered financial reports.

Use returned eligible-income and approved-expense totals; show withheld income
separately. Pending/rejected spending is not actual approved spending. Display
source breakdowns by source type and actual source name. Per-event detail can
show all transaction states even where totals exclude some entries.

Required controls: **Generate/View Report**, **Download PDF**, **Download CSV**,
and **Print** on the dashboard and relevant report screens. Fetch export bytes
with Authorization, inspect status/content type, use `Content-Disposition` for
the filename, then save/share/open a trusted PDF viewer or local print-ready HTML.
Do not open a bare protected API URL in an external browser and assume the token
is attached. HTML is print-ready; native printing/file handling is the frontend's
responsibility. A JSON error body must not be saved as a PDF. On Flutter Web,
backend CORS must allow the deployed origin and expose the filename header.

There is no dedicated raw inventory/user/receipt bulk-export endpoint. Do not
advertise these as backend-generated reports without an agreed extension.

## 12. Proposal letters and SDS oversight

| UI action | API | Permission/state |
|---|---|---|
| List letters | `GET /proposal-letters` | Treasurer/Adviser/Admin scoped; Super Admin and SDS school-wide. Officers have no access. |
| View/open letter | `GET /proposal-letters/{letter_id}` | Show title, event ID, submitted-by ID, time; preview/open returned `document_url`. |
| Upload Letter | `POST /proposal-letters` | Treasurer/Adviser/Admin/Super Admin; multipart `event_id`, `title`, `file`. PDF/JPEG/PNG, maximum 10 MB. |

SDS must have a standalone letter list/detail screen without calling forbidden
event/finance APIs. Letter upload is separate from event submission/approval;
SDS cannot approve events. No letter Edit/Delete/review-status endpoints exist.

## 13. Administration: setup, roster, accounts and audit

| UI action | API | Permission/state |
|---|---|---|
| Department lookup | `GET /departments` | Admin assigned department; Super Admin all departments. |
| Create Department | `POST /departments` | Super Admin; `code`, `name`, optional `description`. |
| Organization lookup | `GET /organizations` | Admin assigned organization; Super Admin all organizations. |
| Create Organization | `POST /organizations` | Super Admin; `code`, `name`, `department_id`. |
| Create organization Admin | `POST /auth/register/admin` | Super Admin; `full_name`, `email`, `organization_id`, `department_id`, optional `position`. Temporary password email; no password field in this request. |
| Create SDS account | `POST /auth/register/sds` | Super Admin; `full_name`, `email`, optional `position`; temporary-password setup. |
| List approved roster | `GET /cite-members` | Admin/Super Admin; filters `department_id`, `organization_id`, `claimed`. |
| Add roster entry | `POST /cite-members` | Admin/Super Admin; `full_name`, `email`, member `role`, optional position, scope as required. This is not an activated account. |
| Edit unclaimed roster | `PATCH /cite-members/{member_id}` | Member role/position; organization transfer only Super Admin. Name/email are NOT editable via this PATCH. |
| Delete unclaimed roster | `DELETE /cite-members/{member_id}` | Admin/Super Admin; claimed entries cannot be deleted. |
| Registered accounts | `GET /users` | Admin manages assigned organization's member accounts; Super Admin broader access. Filters: `department_id`, `organization_id`, `is_active`, `is_suspended`. |
| Change access / Suspend / Restore / Transfer | `PATCH /users/{user_id}/access` | Member role, position, `is_suspended`; transfer via `organization_id` only Super Admin. |
| Repair Admin assignment | `PATCH /users/{user_id}/department` | Super Admin; BOTH `department_id` and `organization_id`; separate legacy repair UI if needed. |
| Audit history | `GET /audit-logs` | Admin scoped; Super Admin global; `limit`, `offset`. Read-only action/entity/actor/time/details. |
| Connectivity check | `GET /health` | Public infrastructure endpoint; developer diagnostics, not a required user menu. |

Required admin UI: distinguish **Approved Roster** from **Registered Accounts**.
Unclaimed entries get Edit/Delete; claimed entries link to Manage Account Access.
Suspend/Restore needs a confirmation dialog explaining access revocation, not a
fake Delete User button. Suspension takes effect even for existing tokens on
subsequent requests. Restoration does not verify a pending registration or bypass
password setup. Admin cannot elevate members to Admin/SDS, transfer scope, modify
its own access, or change Super Admin access. Claimed roster users must retain a
member role. Transferring an account does NOT transfer historical records.

There is no public Create Super Admin screen/API (institution-controlled CLI
bootstrap), no Delete User API, and no Edit/Delete department/organization or
audit-record endpoints. Avoid buttons that imply these operations are supported.

## 14. Delivery tracker and acceptance tests

For EACH action table row, track the following in the frontend team's work board:

| Screen/action | API wired | Role/scope/state checks | Loading/errors | Refresh after success | Device/web test | Evidence |
|---|---|---|---|---|---|---|
| Example: Categories / Create Category | Not yet / Done | Not yet / Done | Not yet / Done | Not yet / Done | Not yet / Done | Screenshot + test record ID |

A supported alternative API path (e.g. OCR text versus image scanning, legacy PDF
versus generic export) may be marked Covered by the chosen flow. Infrastructure
and legacy-repair endpoints may be marked Diagnostic/Admin-only. Unsupported
operations must be marked Backend extension needed, not silently treated as Done.

Minimum end-to-end sign-off checklist, performed in the APP, not only Swagger:

- [ ] Test navigation with all six roles; officers have no operational writes,
  SDS sees letters only, same-department organizations remain isolated.
- [ ] Add roster entry -> register -> verify OTP -> confirmation result -> login.
  Test resend/expired OTP, password reset and mandatory initial-password setup.
- [ ] Load inbox/badge and mark own notification read, including as Officer.
- [ ] Admin creates a category from a visible UI button, opens it, edits it,
  sees it in event/expense pickers, deletes an unused category, and gets a useful
  message trying to delete an in-use category. No direct remaining-budget editor.
- [ ] Create event with required year/semester/scope; reject invalid/null metadata.
  Submit Treasurer proposal -> Adviser approval -> Admin final approval.
  Test Adviser-origin proposal, Admin-origin independent review, blocked
  self-approval, wrong-stage controls, rejection/edit/resubmit and timeline.
- [ ] Repair missing legacy academic metadata as Admin without replacing known
  fields. Treat `pending`, `pending_adviser`, `pending_admin` correctly.
- [ ] Create expense with actual category/event and reviewed asset/consumable
  lines; view details/items; edit allowed pending fields; delete an unreceipted
  pending expense; reject deletion and protected-field edits after receipt.
- [ ] Camera/gallery scan -> editable preview -> save real Expense; also verify
  the chosen upload/parse flow, invalid files, service failure and manual fallback.
- [ ] Review expense independently; test category/event over-budget failures,
  receipt pending/rejected guard and approval-history display.
- [ ] Record actual income for each source type; filter by event; show source,
  purpose/date and receipt-review status. No unsupported income Edit/Delete.
- [ ] Record receipt purpose and exact transaction association; duplicate file,
  URL/reference rejection; similar-receipt pending queue/comparison; independent
  Clear/Reject with reason; verify withheld income and blocked expense approval.
- [ ] Before purchase completion, expense approval leaves stock unchanged.
  Complete fully paid/received asset purchase -> quantity/ledger update once;
  repeat completion fails; view provenance; confirm new catalog draft without
  incrementing stock again; consumables are not automatically stocked.
- [ ] Admin creates/edits event-linked inventory, filters drafts/low stock/event,
  records acquisition/donation/issue/return/disposal/adjustment with reason;
  verifies ledger and stock refresh, over-issue/over-return rejection, unit and
  deletion/history guards. No quantity PATCH or manual purchase movement.
- [ ] Admin repairs missing primary event and legacy movement metadata without
  altering quantity. Unauthorized roles cannot access repair controls.
- [ ] Dashboard displays live status/stock/flag/budget values; chart and flagged
  queue work; recommendation handles both sufficient and insufficient history.
- [ ] Event/category reports and weekly/monthly/school-year/semester financial
  reports work with departmental/organizational filters; totals exclude pending/
  rejected spending and withheld income. Download PDF/CSV and print from actual
  dashboard/report controls; exported filters/totals match displayed report.
- [ ] Upload/open PDF or image proposal letter; SDS can read school-wide letters
  without accessing underlying event/finance data. Officer cannot access letters.
- [ ] Super Admin creates department/organization/Admin/SDS; Admin manages
  unclaimed roster and member access; suspend/restore and Super Admin transfer
  enforce restrictions and retain historical ownership; audit records are visible.
- [ ] Empty/loading/offline/expired-token/suspended-account/server-validation/
  conflict/failed-upload states are tested. No false success or sample-data fallback.

## 15. Deployment prerequisites and explicit backend boundaries

Backend/operator must verify migrations 001–007, real historical ownership/event
links/academic labels, budget triggers, reachable API, allowed web origins,
Supabase storage buckets, email settings, and OCR configuration before production
sign-off. Automated backend tests do not prove those live integrations work.

Known boundaries requiring backend discussion, NOT frontend-only workarounds:

- Income corrections/deletion and standalone file-first income receipt creation.
- Event completion endpoint and arbitrary submitted-history editing.
- Editable saved expense line items and rejected-expense resubmission.
- General transaction duplicate prevention when no receipt is attached; receipt
  duplicate detection is not universal transaction deduplication.
- Private/signed receipt and letter file access if institution policy requires it.
- Consumable stock integration beyond the current asset-only purchase flow.
- Push notifications for reviews/events and generalized notification actions.
- General list pagination/search/scope filters, reviewer display names, and
  additional export formats/entities not provided by the current API.

Related backend handoffs:

- [Roles and permissions](ROLES_AND_PERMISSIONS.md)
- [Core system features](CORE_SYSTEM_FEATURES.md)
- [Financial management](FINANCIAL_MANAGEMENT.md)
- [Inventory management](INVENTORY_MANAGEMENT.md)

Do not mark the frontend complete until every applicable supported action is
reachable and the acceptance checklist has actual UI test evidence.
