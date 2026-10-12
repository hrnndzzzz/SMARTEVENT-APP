# SMARTEVENT End-User System Guide

> Pre-Phase-1 presentation snapshot. The new backend adds a seventh role,
> Signatory, and sequential institutional approvals after Admin review. See
> [Phase 1 implementation](PHASE_1_IMPLEMENTATION.md). Update this guide and its
> previously exported PDF before presenting the new workflow to testers; frontend
> integration and live deployment are not yet certified.

## Purpose of this guide

SMARTEVENT is a role-based system for student-organization event planning,
budget monitoring, financial recording, receipt verification, inventory
management, proposal-letter submission, and reporting.

This guide explains what an end-user can do, which role is responsible for each
action, and how records move through the system. It is intended to be shown to
test participants before they use the application.

The guide describes the backend capability currently implemented in the
repository. A backend API operation is not, by itself, proof that the Flutter
application already exposes the corresponding button or screen. During user
testing, both the workflow and the application screen should be verified.

## 1. System at a glance

The system provides:

- Secure account registration, email verification, login, password setup and
  password recovery.
- Organization-scoped access so users see only records belonging to their
  assigned organization and department.
- Event proposal and approval workflows with academic-year and semester data.
- Budget categories and remaining-budget monitoring.
- Expense recording, itemized expense lines, receipt upload, OCR assistance,
  receipt duplication checks and independent review.
- Income recording with fund-source classification.
- Inventory catalog management, event-linked stock movements, low-stock views,
  purchase completion and transaction history.
- Proposal-letter upload and controlled access.
- Dashboards, spending trends, flagged-expense queues, budget recommendations,
  financial reports and PDF/CSV/HTML exports.
- Personal notifications and read-only administrative audit history.

The backend contains 89 functional API operations organized across 19 API areas, plus
`/health` for a basic connectivity check.

## 2. Roles and responsibilities

| Role | Main responsibility | Typical permissions |
|---|---|---|
| **Super Admin** | School-wide system administration and oversight | Creates departments, organizations, Admin and SDS accounts; manages assignments; can access all operational records; can perform supported administrative actions and final reviews. |
| **Admin** | Organization administration | Manages the roster, member access, categories, inventory catalog, events, finances, reports and audit history for the assigned organization. Reviews submissions from other users. |
| **Adviser** | Independent review and event oversight | Creates own event drafts, reviews events and expenses submitted by others, records inventory movements, reads reports and uploads proposal letters. |
| **Treasurer** | Financial and stock recording | Creates own event drafts, records income and expenses, manages own pending expenses and receipts, completes own approved asset purchases, records inventory movements and uploads proposal letters. |
| **Officer** | Operational monitoring | Read-only access to the assigned organization’s operational records, reports and analytics. May change their own password and read/mark their own notifications. |
| **SDS Staff** | School-wide proposal-letter oversight | Reads proposal letters across the school and manages their own account and notifications. Has no operational event, finance, inventory or report access. |

### Important access rules

1. **Role, scope, ownership and record status all matter.** A user may have
   the correct role but still be blocked if the record belongs to another
   organization, belongs to another user, or is at the wrong workflow stage.
2. **Department membership does not grant cross-organization access.** Two
   organizations may be in the same department and still remain isolated.
3. **Officer is operationally read-only.** A position label such as President
   or Secretary does not add write permission.
4. **Super Admin is not exempt from independent review.** The person who
   submitted an event, expense or receipt cannot approve or reject that same
   record.
5. **SDS Staff is separate from operational roles.** SDS Staff can see proposal
   letters but cannot approve events or read financial or inventory records.

## 3. Account and registration workflow

### Initial setup

1. The institution appoints the Super Admin.
2. The Super Admin creates the department and organization records.
3. The Super Admin creates Admin and SDS Staff accounts.
4. The Admin adds approved Adviser, Treasurer and Officer members to the
   organization roster.

### Member registration

1. The member enters the email address already placed on the roster.
2. The member chooses a password and requests registration.
3. The system sends a one-time verification code by email.
4. The member enters the code.
5. The account becomes active automatically if the roster assignment is still
   valid.
6. The member logs in and receives the role, name, position, department and
   organization assigned by the roster.

Users cannot select their own elevated role during registration. An Officer
cannot register as Treasurer simply by choosing Treasurer in the app.

### Password and session behavior

- Admin-created accounts receive a temporary password and must change it before
  using the operational system.
- Forgot-password recovery uses a one-time code sent by email.
- Five failed login attempts temporarily lock an account for 15 minutes.
- Password changes and resets invalidate previous access tokens; the user must
  log in again.
- The application clears the token locally when the user logs out. There is no
  server-side logout or refresh-token operation in the current backend.
- Suspended or unverified users cannot access protected functions.

## 4. Main system workflows

### 4.1 Event proposal and approval

Events require a title, event date/details as applicable, school year, semester,
event scope and a valid organization/department assignment. The allowed values
are:

- School year: consecutive years such as `2026-2027`.
- Semester: `1st`, `2nd` or `summer`.
- Event scope: `departmental` or `organizational`.

#### Who can create an event?

Treasurer, Adviser, Admin and Super Admin can create events. Officers cannot
create or submit event proposals.

#### Approval paths

| Proposer | Workflow |
|---|---|
| Treasurer, Admin or Super Admin | Draft → Adviser review → Admin/Super Admin final review → Approved |
| Adviser | Draft → Admin/Super Admin final review → Approved |
| Any proposal rejected | Rejected → proposer edits → resubmits → review starts again |

More specifically:

1. The proposer saves a draft or submits the proposal.
2. Adviser review is required for Treasurer/Admin/Super Admin proposals.
3. Admin or Super Admin gives the final approval.
4. An Adviser proposal goes directly to Admin/Super Admin final review.
5. A reviewer may reject a proposal with remarks.
6. The original proposer edits the rejected proposal and resubmits it.
7. The system keeps the approval and rejection history.

An Adviser can approve or reject only the adviser-review stage. Admin and Super
Admin can approve the final admin-review stage; Admin/Super Admin can reject a
proposal at either pending stage. The original proposer cannot approve or reject
their own proposal.

Only draft events can be deleted. Submitted, approved or rejected events must
remain in the workflow history. The current backend accepts a `completed`
status in responses for legacy compatibility, but there is no separate
Complete Event action.

### 4.2 Categories and budgets

Categories represent budget groupings such as supplies, transportation or
venue-related spending.

- Admin and Super Admin create, edit and delete categories.
- All operational roles may view categories within their scope.
- A category includes an allocated budget, remaining budget and low-balance
  threshold.
- A category referenced by an event or expense cannot be deleted.
- Changing an allocation adjusts the remaining budget by the allocation change,
  but the system will not allow the remaining budget to become less than money
  already committed/spent.
- The remaining budget is calculated and controlled by the backend/database;
  users should not manually overwrite it in the app.

### 4.3 Expense workflow

#### Recording an expense

Treasurer, Admin and Super Admin can record expenses. An expense starts as
**Pending** and may include:

- Category and optional event link.
- Description or purpose.
- Amount and expense date.
- Asset or consumable item lines.
- Receipt information or a receipt image.

The category, event and expense must belong to the same organization and
department. Asset lines require a positive whole-unit quantity and unit.

#### Review

1. A Treasurer/Admin/Super Admin records the pending expense.
2. An independent Adviser, Admin or Super Admin reviews it.
3. The reviewer approves or rejects it with optional remarks.
4. Approval checks category budget and, when present, event budget.
5. When approved, the backend/database deducts the committed budget.

The expense recorder cannot review their own expense. Expense review is a
single review step; it is not the two-stage event approval process.

Pending expenses may be edited or deleted by the Treasurer who recorded them or
by an authorized Admin. Approved and rejected expenses cannot be edited. An
expense with a recorded receipt cannot be deleted; it must remain available for
review and audit.

The current backend does not provide an expense resubmission action after
rejection, and expense item lines are not edited through the general expense
edit operation.

### 4.4 Receipt scanning, OCR and duplicate review

Receipts can be captured using an image upload, scanned before an expense is
saved, or parsed from text produced by on-device OCR.

The scan result is only a preview. It does not create an expense until the user
reviews the merchant, date, amount and item information and submits the expense.
OCR mismatches are shown as flags and must be reviewed by a person.

Receipt rules:

- Every receipt belongs to exactly one expense or income record.
- The receipt must have a purpose, event link and matching amount.
- The backend checks duplicate URLs, uploaded-file hashes and normalized
  merchant/reference combinations within the organization.
- A similar merchant/amount/date combination is flagged for review.
- An Adviser, Admin or Super Admin who did not record the receipt must clear or
  reject the similarity flag and provide a reason.
- Pending or rejected receipt review blocks expense approval and purchase
  completion.
- Reviewed receipt evidence is immutable.

Receipts and proposal letters are accessed through authorized short-lived file
links. A file link currently expires after five minutes; the app should request
a new link when it expires.

### 4.5 Income and fund sources

Treasurer, Admin and Super Admin can record income tied to an event. Each income
record includes source, source type, purpose, amount and date received.

Supported source types are:

- Registration fees
- Sponsorship
- Donation
- Other

Operational users may view income. There is no income edit or delete operation
in the current backend, so corrections require an agreed administrative/data
correction procedure rather than a client-side workaround.

Income with a pending or rejected receipt review is shown as **withheld** and is
not included in eligible income totals until resolved.

### 4.6 Asset purchase completion and inventory

Approval of an asset expense does **not** immediately add stock. Stock is added
only after payment and delivery details are recorded.

#### Completed-purchase workflow

1. Treasurer/Admin records an event-linked expense with asset lines.
2. The expense has a purpose-bearing receipt.
3. An independent Adviser/Admin/Super Admin approves the expense.
4. Payment is completed and the goods are actually received.
5. The Treasurer who recorded the expense, or an authorized Admin/Super Admin,
   submits payment and delivery details.
6. The system verifies full payment, receipt matching, vendor, payment method,
   payment reference, paid date, received date and every asset quantity/unit.
7. The system adds stock and creates one purchase ledger movement per asset line.
8. A newly created catalog item is marked as a draft for Admin confirmation.
9. Confirming the draft makes it available for normal movements; it does not
   add the purchase quantity a second time.

The same purchase cannot be completed twice. Consumable lines remain financial
records and are not automatically added to inventory.

#### Inventory catalog and movements

- Admin and Super Admin create, edit, confirm and delete catalog items.
- A new catalog item requires an intended event link.
- Adviser, Treasurer, Admin and Super Admin can record authorized movements.
- Officers can view inventory but cannot change stock.
- SDS Staff has no operational inventory access.

Supported movement types include:

| Movement | Meaning |
|---|---|
| Opening balance | Verified starting stock when an item is created |
| Acquisition | Stock received outside the completed-purchase flow |
| Donation | Stock received as a donation |
| Purchase | Generated by completed purchase only |
| Issue | Stock issued for an event |
| Return | Stock returned from the same event |
| Disposal | Damaged, lost or retired stock |
| Adjustment | Documented physical-count correction |
| Legacy | Historical row awaiting administrator classification |

The backend prevents negative stock, excessive returns and undocumented
purchase movements. Stock changes and their ledger records are stored together.
Items with stock, purchase evidence or transaction history cannot be deleted;
they should be retired through a reason-bearing disposal movement.

### 4.7 Proposal letters

Treasurer, Adviser and Admin can upload a PDF, JPEG or PNG proposal letter linked
to an event. The organization can read its letters. SDS Staff and Super Admin
can read proposal letters school-wide. Officers cannot access proposal letters.

The current backend supports upload and read operations only. Letter editing and
deletion are not currently provided.

### 4.8 Dashboard, analytics and recommendations

Operational users can view a scope-limited dashboard containing:

- Number of categories.
- Total allocated and remaining category budgets.
- Event counts by status.
- Expense counts by status.
- Flagged-expense count.
- Low-stock item count.
- Inventory drafts awaiting confirmation.

Additional analytics include:

- Approved-spending trends grouped by expense creation month.
- Flagged-expense queue for Adviser/Admin/Super Admin.
- Event-budget recommendations based on at least two past approved or completed
  events in the selected category.

Recommendations are advisory only. A suggestion is not a budget approval and is
not generated when there is insufficient historical data.

### 4.9 Reports and exports

Operational users can view reports by category, event and financial period.
Financial periods are:

- Weekly
- Monthly
- School year
- Semester

Academic reports may also be filtered by departmental or organizational event
scope. Weekly and monthly reports use transaction dates. School-year and
semester reports use the event’s recorded academic labels.

Reports distinguish:

- Eligible income.
- Withheld income from pending/rejected receipt reviews.
- Approved expenses.
- Unassigned approved expenses in applicable calendar reports.
- Net balance.
- Income source breakdown.
- Event transactions and receipt information.

Dashboard, event, category and financial reports can be exported as PDF, CSV or
print-ready HTML. The application must download or open the returned file using
the authenticated request; tokens must never be placed in a report URL.

### 4.10 Administration, access control and audit

Super Admin functions:

- Create departments and organizations.
- Create Admin and SDS Staff accounts.
- Assign or transfer accounts to organizations.
- View school-wide administrative history.

Admin functions:

- Add, list, update and remove unclaimed roster entries.
- Change the role, position or suspended state of eligible organization members.
- View users in the assigned organization.
- View organization-scoped audit history.

Claimed roster entries cannot be deleted. Their registered accounts are managed
through user access controls instead. The current backend does not provide a
general Delete User action, and department/organization edit/delete endpoints
are not available.

Audit entries record important access, roster, financial, event and inventory
changes. Audit history is read-only to end-users.

### 4.11 Notifications

Each authenticated user has a personal inbox with:

- Notification list.
- Unread-only filter.
- Unread count.
- Mark-as-read action.

The implemented notification flow currently focuses on registration
confirmation and email delivery/retry status. Event-review push notifications,
device push delivery, mark-all-read and notification deletion are not currently
implemented.

## 5. Role-based test walkthrough

The following sequence is suitable for a controlled user-acceptance test.

### Test 1: Account setup

1. Super Admin creates a department and organization.
2. Super Admin creates an Admin and an SDS Staff account.
3. Admin creates one Adviser, one Treasurer and one Officer roster entry.
4. Each rostered member registers with the matching email.
5. Each member verifies the email code and logs in.
6. Confirm that the role, organization and department come from the roster.
7. Confirm that an unrostered email is rejected.

### Test 2: Role and scope boundaries

1. Log in as Officer and confirm operational records are visible.
2. Try a create, edit, delete, approval or movement action as Officer; it should
   be rejected.
3. Log in as SDS Staff and confirm only proposal letters, profile and
   notifications are available.
4. Try to access another organization’s event, expense or inventory item; it
   should be rejected or hidden.
5. Suspend a member as Admin and confirm their protected access stops.

### Test 3: Event approval

1. Admin creates a category with an allocation.
2. Treasurer creates and submits an event.
3. Adviser approves the adviser-review stage.
4. Admin or Super Admin gives final approval.
5. Try self-approval as the proposer; confirm it is blocked.
6. Reject a test event, edit it as the proposer and resubmit it.
7. Inspect the approval history and confirm prior decisions remain recorded.

### Test 4: Expense and receipt review

1. Treasurer records a pending expense linked to the category and event.
2. Upload or scan a receipt and review the OCR result.
3. Create or save the expense after correcting any OCR discrepancy.
4. Adviser reviews the receipt similarity flag if one is raised.
5. Adviser/Admin approves or rejects the expense.
6. Confirm that approval is blocked when the receipt review is unresolved or
   when the category/event budget is insufficient.
7. Confirm that approved spending changes the backend budget totals.

### Test 5: Purchase-to-inventory workflow

1. Create an approved expense with an asset line and receipt.
2. Confirm that approval alone does not increase inventory.
3. Complete the purchase with full payment, vendor, dates, method, reference,
   quantity and unit.
4. Confirm that stock and purchase-ledger history are created once.
5. Confirm that a new item requires Admin draft confirmation before manual use.
6. Issue stock for an event and return it.
7. Try an over-return, negative-stock movement or repeat purchase completion;
   each should be rejected.

### Test 6: Reports and exports

1. Open the dashboard as Officer, Adviser and Admin and compare scope.
2. View event, category and financial reports.
3. Test weekly/monthly and school-year/semester filters.
4. Confirm withheld income is shown separately from eligible income.
5. Download PDF, CSV and HTML exports using an authenticated session.

## 6. Rules users will commonly encounter

| Situation | Expected result |
|---|---|
| Not logged in or expired token | `401` authentication error; log in again. |
| Wrong role or organization scope | `403` access denied. |
| Invalid field, date, amount or file | `422` validation error. |
| Action conflicts with status, budget, duplicate evidence or history | `409` workflow conflict. |
| Record no longer exists | `404` not found. |
| Email, OCR or storage service unavailable | `502`/`503`; preserve the user’s input and retry safely. |

The application should show the backend explanation in plain language and must
not silently retry financial writes, approvals or purchase completions.

## 7. Current boundaries to explain before testing

The following are intentionally not available in the current backend:

- Income edit and delete.
- Expense-line editing through the expense edit action.
- Rejected-expense resubmission.
- Event completion action.
- General editing of submitted/approved event history.
- Proposal-letter edit and delete.
- Department and organization edit/delete.
- General user deletion; use suspension/restoration where supported.
- Automatic consumable-stock integration.
- Event-review device push notifications.
- Refresh-token and server-side logout workflow.
- Standalone file-only income receipt creation without the related transaction.

Testers should not expect these actions or attempt to bypass them through local
state, direct database writes or unsupported API calls.

## 8. Environment readiness before end-user testing

Before inviting users, the test environment owner should verify:

1. Database migrations are applied in order, including the security hardening
   migration required by the current deployment plan.
2. The database connection, email sender, receipt/proposal storage and OCR
   credentials are configured for the test environment.
3. Receipt and proposal-letter buckets are private and file access is tested
   through authenticated short-lived links.
4. HTTPS, allowed frontend origins and server-only secrets are configured for
   any non-local test deployment.
5. Test accounts cover Super Admin, Admin, Adviser, Treasurer, Officer and SDS
   Staff.
6. The frontend exposes the actions required by the test plan; Swagger alone is
   not evidence that the mobile application is complete.
7. Historical records are not modified or invented merely to pass a test.

## 9. Verification note

At the time this guide was prepared, the backend test suite completed with
**310 passed tests and 4 dependency deprecation warnings**. These tests provide
regression evidence for the application code and authorization workflows, but
they do not, by themselves, certify the live PostgreSQL migrations, external
email/storage/OCR services, production security configuration or Flutter UI
completion.

## 10. Backend feature areas

For technical traceability, the current API is organized as follows:

| Area | Backend prefix | Main functions |
|---|---|---|
| Authentication | `/auth` | Registration, OTP, login, profile, role information, password change/reset |
| Notifications | `/notifications` | Inbox, unread count, mark read |
| Departments | `/departments` | Super Admin creation and scoped lookup |
| Organizations | `/organizations` | Super Admin creation and Admin lookup |
| Users | `/users` | User listing, Admin assignment and access changes |
| Roster | `/cite-members` | Add, list, update and remove unclaimed members |
| Audit | `/audit-logs` | Read administrative audit history |
| Categories | `/categories` | Budget-category CRUD and read access |
| Events | `/events` | Proposal creation, editing, submission, review and history |
| Expenses | `/expenses` | Expense CRUD, OCR, receipts, review and purchase completion |
| Income | `/incomes` | Income recording and listing |
| Receipts | `/receipts` | Receipt listing, upload, duplicate review and evidence access |
| Inventory | `/inventory` | Catalog, movements, low-stock, draft confirmation and repairs |
| Proposal letters | `/proposal-letters` | Event-linked document upload and access |
| Analytics | `/analytics` | Dashboard, trends, flagged-expense queue and export discovery |
| Recommendations | `/recommendations` | Historical event-budget suggestions |
| Reports | `/reports` | Category, event and consolidated financial reports |
| Export downloads | `/reports/.../export` | PDF, CSV and HTML report files |
| File access | `/files` | Authorized short-lived links for stored files |
| Health | `/health` | Basic API connectivity response |
