# Core System Features — backend handoff

This phase implements the adviser's Core System Features in the backend only.
Flutter screens, dashboard buttons, mobile printing/sharing, and notification
badges belong to the frontend team. Financial and inventory enhancements are
not expanded by this phase; exports reuse the financial queries already present.

## Requirement coverage

| Adviser recommendation | Backend behavior |
| --- | --- |
| Registration confirmation | Registration OTP email, then a persistent personal confirmation plus a separate success email after verification. Failed success emails are retryable. |
| Automatic admission subject to requirements | Administrator-approved roster email, allowed member role, valid organization/department pair, unclaimed roster, verified unexpired OTP, and no suspension. Eligibility is checked again before activation. No separate manual approval is needed. |
| School year required on creation | Required consecutive YYYY-YYYY, starting at 1900 or later; semester and event scope also required. |
| Consistent event school years | Null-clearing is rejected; submission/approval require complete academic metadata; scoped year filters and legacy repair are provided. Database enforcement is in migration 005. Legacy completeness requires a data cleanup before constraint validation. |
| Dashboard download/print | Authenticated discovery endpoint plus PDF, CSV, and print-ready HTML exports for dashboard, event, category, and consolidated financial reports. |

## Deployment (before testing against Supabase)

1. Back up the database and confirm migrations 001–004 are applied.
2. Apply `scripts/005_core_system_features.sql` in the Supabase SQL editor.
   It creates the notification inbox, indexes, and event academic-metadata check.
   The private notifications table enables RLS without public policies: the
   backend must use its trusted database connection with suitable access.
3. `NOT VALID` does not guess academic years or remove legacy events. It preserves
   existing rows but enforces the check on every new/updated event. Repair old
   events before further operations that update them (including budget triggers).
4. Use `GET /events?missing_school_year=true` to find null years within your
   authorized scope. Check SQL for other missing/invalid metadata as well:

   ```sql
   SELECT id, title, school_year, semester, event_scope
   FROM events
   WHERE school_year IS NULL OR semester IS NULL OR event_scope IS NULL
      OR semester NOT IN ('1st', '2nd', 'summer')
      OR event_scope NOT IN ('departmental', 'organizational')
      OR NOT CASE WHEN school_year ~ '^[0-9]{4}-[0-9]{4}$' THEN
          substring(school_year, 1, 4)::integer >= 1900
          AND substring(school_year, 6, 4)::integer = substring(school_year, 1, 4)::integer + 1
          ELSE FALSE END;
   ```

   Admins can fill missing metadata through the repair endpoint below. Already
   recorded values cannot be replaced through that endpoint. Invalid but non-null
   historical values require a reviewed database correction; do not infer them
   from `created_at`. Regular drafts can be corrected through the usual PATCH.
5. After correcting every row, execute the validation and NOT NULL statements
   commented at the end of migration 005. This completes legacy enforcement.
6. Configure `RESEND_API_KEY` and a verified `RESEND_FROM_EMAIL` sender. The
   `onboarding@resend.dev` development sender is restricted to `RESEND_TEST_EMAIL`.
   Registration OTP delivery failure returns 503 and rolls back registration;
   confirmation delivery failure does not undo a verified account.
7. Schedule `python -m scripts.deliver_notifications --limit 100`, for example
   every five minutes. This sends real emails; run it only in the intended
   environment. It retries pending/failed messages and skips sent messages.
   Each notification uses a stable provider idempotency key to reduce duplicate
   delivery on retries; this is not an unlimited exactly-once delivery guarantee.
8. Start the API and use `/docs` or `/openapi.json` for the current contracts.

## Frontend contracts

All operational and personal inbox endpoints use
`Authorization: Bearer <access_token>`. Public registration and verification do
not require login. Never put JWTs in download URLs.

### Registration

1. `POST /auth/register`

   ```json
   {"email":"approved.member@example.com","password":"ChosenPassword123!"}
   ```

   Returns 201 with `UserOut`, `is_active=false`, and the assigned roster role.
   Show the verification screen; do not open the dashboard yet. Unknown roster
   email/invalid assignment returns 403; reused roster/email returns 400;
   unavailable OTP delivery returns 503. Roles and organization cannot be chosen
   by the self-registering user.

2. `POST /auth/verify-otp`

   ```json
   {"email":"approved.member@example.com","otp_code":"123456"}
   ```

   Success response:

   ```json
   {
     "detail":"Account successfully verified and automatically approved. You can now log in.",
     "registration_status":"approved",
     "notification_id":"notification-uuid",
     "confirmation_email_status":"sent"
   }
   ```

   The email status may instead be `failed` or `pending`; approval is still
   successful. Already active accounts return approved status without generating
   a second notification, with notification/email fields null. Incorrect/expired
   OTP returns 400; revoked eligibility or suspension returns 403.

3. `POST /auth/resend-otp` with `{"email":"approved.member@example.com"}`.
   Successfully issued codes invalidate older registration codes. The generic
   response intentionally does not reveal account existence or delivery status.
4. `POST /auth/login` uses form fields `username=<email>` and `password=<password>`.
   Verification is required before login. Provisioned admins/SDS continue using
   their existing emailed temporary-password/change-password workflow.

### Notification badge and inbox

- `GET /notifications/unread-count` returns `{"unread_count":1}`.
- `GET /notifications?unread_only=false&limit=50&offset=0` returns newest first.
  Each item includes `id`, `kind`, `title`, `body`, `read_at`, `email_status`,
  and `created_at`. Maximum page size is 100.
- `PATCH /notifications/{notification_id}/read` takes no body and returns the
  updated item. It is idempotent. Non-owned IDs return 404, including for admins.

Officers may mark their own notification read. This personal action is not an
operational-record edit and does not relax their view-only role.
These are persisted in-app notifications, not Firebase push notifications.

### Events

`POST /events` example (organization-scoped users inherit their assignment):

```json
{
  "title":"Student Leadership Seminar",
  "school_year":"2026-2027",
  "semester":"1st",
  "event_scope":"organizational",
  "status":"draft",
  "allocated_budget":1000
}
```

Super Admin supplies organization and department IDs. Existing category and
ownership restrictions remain in force. School-year/semester/scope errors return
422. PATCH may omit these fields but may not explicitly clear them with null.

- `GET /events?school_year=2026-2027`: scoped event filter.
- `GET /events/school-years`: distinct authorized years, descending, for dropdowns.
- `GET /events?missing_school_year=true`: legacy null-year records.
- `PATCH /events/{event_id}/academic-metadata`: Admin/Super Admin fills missing
  legacy academic fields in any status. Body contains `school_year`, `semester`,
  `event_scope`. Existing valid values must be preserved. The repair is audited;
  trying to overwrite completed metadata returns 409. No budget/status changes.
- Event submission/approval with incomplete academic metadata returns 409.
- Event review uses `pending_adviser` -> `pending_admin` -> `approved`.
  Legacy `pending` is treated as awaiting adviser review. Adviser proposals
  start at `pending_admin`; all other authorized proposers start at
  `pending_adviser`. Officers remain view-only. Admin and Super Admin proposals
  are not auto-approved: the original proposer cannot approve or reject them.
  Rejected proposals can be edited and resubmitted, retaining review history;
  resubmission uses the original proposer's role, not the resubmitter's role.

### Dashboard downloads and printing

Start with `GET /analytics/dashboard/exports`. This returns relative dashboard
download URLs, event/category/financial URL templates, supported MIME types,
and available financial filters. All URLs must be fetched with the current JWT.

| Endpoint | Query parameters |
| --- | --- |
| `/reports/dashboard/export` | `format=pdf`, `csv`, or `html` |
| `/reports/event/{event_id}/export` | `format` |
| `/reports/category/{category_id}/export` | `format` |
| `/reports/financial/export` | `format`, required `period`, optional `reference_date`, `school_year`, `semester`, `event_scope` |

`period` is `weekly`, `monthly`, `school_year`, or `semester`. Academic periods
require `school_year`; semester periods also require `semester` (`1st`, `2nd`,
`summer`). Scope is `departmental` or `organizational`. Existing financial JSON
and `/reports/financial.pdf` routes remain compatible.

Frontend implementation:

1. Fetch response **bytes**, not JSON, with the Authorization header.
2. Use `Content-Type` and `Content-Disposition` for file format/name. CORS exposes
   Content-Disposition to browser clients. PDF/CSV use attachment disposition.
3. Save/share PDF or CSV through the frontend platform's file controls. On Flutter
   web, create a Blob URL from authenticated response bytes, then download it.
4. For Print, fetch `format=html` and show the returned document, then invoke the
   platform/browser print action; alternatively print the PDF through a mobile
   printing package. HTML includes print CSS and Ctrl+P instructions, no scripts.
5. Do not open a raw API URL in a browser expecting it to inherit a Bearer header.
   Dispose temporary Blob URLs/files after use and keep reports private.

Admins, advisers, treasurers, and officers only export their own organization and
department. Super Admin exports global data. SDS is denied operational exports.
Suspended/unverified/password-change-required users remain blocked. Downloads
use no-store headers; CSV guards formula-looking text and HTML escapes content.
Financial CSV is a consolidated summary; event CSV includes actual income and
expense entries. Exports do not fabricate financial data or include receipt images.

## Step-by-step acceptance testing

Use test accounts and test records, not production records.

1. Run `.venv\Scripts\python.exe -m pytest -q -p no:cacheprovider app`.
   These tests use isolated SQLite and mocked email, not Supabase/Resend.
2. As Admin, add an unused officer roster entry to your organization. Register its
   email, confirm OTP delivery, and confirm login is denied before verification.
3. Try an unknown email, reused roster, wrong/expired OTP, and invalid assignment.
   Confirm no account becomes active and no success notification is generated.
4. Verify the valid OTP: expect approved status, success email, and one inbox item.
   Repeat verification: no duplicate confirmation/audit record/email.
5. In a test environment, simulate confirmation email failure; approval remains
   successful and the notification records failed status. Restore delivery and
   run the retry command; expect sent status without an additional inbox item.
6. Log in as that officer, check the badge count, list inbox, and mark the item
   read twice. Try another user's ID: 404. Operational writes must remain 403.
7. Create an event with a valid year. Omit the year, use 2026-2029, or PATCH null:
   expect 422. Re-read the event and confirm its year is retained.
8. Use year filters/dropdowns. As Admin, repair a legacy event missing metadata
   from known records; confirm the audit log. Officer/another organization cannot
   repair it. Submit/approve an incomplete legacy event: 409.
9. As Officer, fetch export discovery and download dashboard/event/category/
   financial data in all formats. Check totals against JSON; pending/rejected
   expenses must not contribute to approved-spending totals. Open HTML and print.
10. Export an event belonging to another organization: 403. Repeat operational
    exports as SDS (403), without JWT (401), or with an invalid format/year (422).
11. Give this document and `/openapi.json` to the Flutter team. Their final UI
    integration should repeat registration, badge, download, and print checks
    on each supported device.

## Verification limits

The backend automated tests cover business rules, report content/structure, and
authorization. They do not establish live PostgreSQL constraint enforcement,
concurrent production transactions, email inbox delivery, or mobile printing.
Validate migration 005 on a staging PostgreSQL database before deploying.
