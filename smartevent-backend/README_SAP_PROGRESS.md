# SAP backend: progress and remaining work

Updated: 31 October 2026 (Asia/Manila)

Tracking: [GitHub issue #9](https://github.com/hrnndzzzz/SMARTEVENT-APP/issues/9)

## Current status

**Both releases are implemented and committed. The complete backend suite passes.
Independent review found no actionable issues. Both draft pull requests are open;
neither release has been merged or deployed.**

| Release | Branch | Status |
| --- | --- | --- |
| 1: form limits, budget fields, API schemas | `fix/sap-backend-core` | Committed through `65d53f3`; 469 backend tests passed |
| 2: withdrawal and notifications | `feat/sap-withdrawal-notifications` | Implementation committed in `2153bf6`; full suite passed; independent review complete |

Review order: [Release 1 — PR #11](https://github.com/hrnndzzzz/SMARTEVENT-APP/pull/11),
then [Release 2 — PR #12](https://github.com/hrnndzzzz/SMARTEVENT-APP/pull/12).
PR #12 targets Release 1's branch until PR #11 merges; retarget it to `develop`
afterward. Both remain drafts for integration/deployment review.

Working checkout: `SMARTEVENT-APP/sap-issue9`.
Starting point: `develop` at `9e076d7` in `SMARTEVENT-APP - Copy`.
The original checkout, SDK edits, and saved SAP stash have been preserved.

## Completed implementation

### Release 1

- Increased additional information from 500 to **4,000 characters**, including
  draft writes and final submission validation.
- Added budget `quantity` (integer, 1–100000, default 1) and optional `unit_cost`.
  Money remains decimal-based; `amount` remains authoritative for totals.
- Added four-column PDF budget addenda. Missing unit cost prints blank.
- Added explicit schemas for all SAP JSON responses and binary PDF documentation.
  Empty drafts, legacy budget rows, nested collections, and hyphenated keys remain
  supported.
- Added regression tests and a [frontend handoff](docs/SAP_ISSUE_9_HANDOFF.md).

Commits: `eb11587` (information limit), `243048a` (budget fields),
`65d53f3` (response schemas and contract).

### Release 2

- Added `POST /events/{event_id}/sap-proposal/withdraw` with `expected_version`.
- Restricted withdrawal to the original authorized proposer, before any current
  SDS review record, signature, or recorded checkpoint.
- Withdrawal restores the proposal/event to draft, clears SDS clearance, and
  preserves submitted revisions, PDFs, verification tokens, and checkpoints.
- Attachment metadata carries forward to the next draft while reusing private
  files and retaining original upload attribution and historical records.
- Added notification payloads containing event/proposal IDs, revision, state,
  and action, plus readable activity-specific wording.
- Reused the inbox and existing email retry worker; distinguished SDS signing
  from final approval.
- Prepared the additive migration
  `supabase/migrations/20261023134616_sap_notification_payload.sql`.
- Added opt-in PostgreSQL migration and concurrent review/withdrawal checks.

### Department review (Moderator and Dean)

- A sent proposal goes to the event's Moderator, then its Dean, before the SDS
  Office sees it; one an adviser sent or created starts with the Dean. Either may
  return it to the draft with remarks. They use the existing
  `POST /events/{event_id}/approve` and `/reject`, and the proposal waits in the
  new `pending_department_review` state.
- A returned proposal says who returned it (`returned_by`: `moderator`, `dean` or
  `sds`). The SDS Office sees a proposal only from the Dean's approval on, or after
  it returned the proposal itself. The Dean's approval checks pre-activity
  readiness again.
- Backend work only; Flutter changes are a separate handoff. See the
  [contract](docs/sap-fo-020-frontend-contract.md#state-and-concurrency) and
  `supabase/migrations/20261030000100_sap_department_review.sql`.

## Verification completed

| Check | Result |
| --- | --- |
| Original SAP baseline | 31 passed |
| Release 1 SAP and new core tests | 48 passed |
| Release 1 entire backend suite | 469 passed |
| Release 2 withdrawal and notification tests | 29 passed |
| Final combined backend suite | 498 passed, 3 PostgreSQL checks skipped |
| PostgreSQL-specific checks without test database configured | 3 explicitly skipped; **not verified on PostgreSQL** |
| PDF visual check | Rendered and inspected addenda with 4,000 information characters, 16 maximum-length budget rows, quantity 100000, and maximum money values |

Focused tests cover long-text round trips, money validation, API responses,
withdrawal access and stale versions, blocked reviews, attachment/history
preservation, rollback, notification privacy, and email retries with a mocked
provider. Existing dependency deprecation warnings remain.

Generated visual samples and OpenAPI output are under ignored `tmp/pdfs/` in
the working checkout. They are verification artifacts, not committed user data.

## Remaining before merge

- [x] Run the full backend suite on the final combined changes: 498 passed.
- [x] Complete an independent code review: no actionable findings.
- [x] Finish Release 2 frontend/deployment instructions and commit the changes.
- [x] Open separate pull requests: Release 1 into `develop`; Release 2 initially
  based on Release 1, then retarget after Release 1 merges.

## Remaining before deployment

- [ ] Identify a disposable PostgreSQL test database. Set
  `SAP_TEST_POSTGRES_URL` explicitly to a database whose name ends in `_test`.
  Run `python -m pytest app/test_sap_postgres.py -q`. These tests create and
  remove unique `sap_test_*` schemas; they never use the application's
  `DATABASE_URL` as a fallback.
- [ ] Reconcile the target's migration history with its actual schema. The
  connected application project has `sap_reviews` and `sap_attachments`, but its
  migration ledger does not list the later review/signature/attachment migration.
  Do not blindly rerun that migration.
- [ ] Apply the department-review migration
  `supabase/migrations/20261030000100_sap_department_review.sql` to staging
  **before** deploying the backend that reads `returned_by`; without the column
  every approve, reject and SAP route fails. After that backend is live, run the
  migration's `UPDATE` once more to label any SDS return made in between (it
  only fills rows with no `returned_by`, so repeating it is safe).
- [ ] Apply the notification-payload migration to staging **before** deploying
  Release 2 backend models. Existing notifications should have null payloads;
  existing grants and row access rules must remain unchanged.
- [ ] Run real staging API/PDF checks, PostgreSQL access/trigger checks, and
  controlled-recipient email delivery/retry checks.
- [ ] Deploy in release order, then monitor validation/serialization errors and
  failed email retries. No live migration, deployment, or real email test has
  been performed during this implementation.

## Frontend work still needed

Flutter changes are a separate handoff:

1. Raise the additional-information UI limit from 500 to 4,000.
2. Edit, save, and reload budget quantity and optional unit cost.
3. Use the documented nested SAP responses and decimal-string money values.
4. Add withdrawal with 403/409 handling and reload after stale-version errors.
5. Use notification payloads to open the relevant proposal; support null payloads
   on older notifications.

## Explicitly deferred

| Item | What must happen first |
| --- | --- |
| Independent organizations / null departments | Design registration, organization ownership, access rules, and PDF signatory behavior together |
| Field-level annotations | Define anchors, authorship, permissions, resolution history, and revision handling |
| Multiple evaluators | Confirm the requirement; keep one evaluator per proposal for now |
| Department name in account response | Separate additive enhancement; `organization_name` already exists |

For implementation decisions and test history, see the
[implementation ledger](docs/SAP_ISSUE_9_IMPLEMENTATION.md).
