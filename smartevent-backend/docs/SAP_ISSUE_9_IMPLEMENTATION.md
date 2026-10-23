# SAP issue #9 implementation ledger

Approved scope: Release 1 raises information to 4000 characters, adds budget quantity
and unit cost, and documents SAP responses. Release 2 adds pre-review withdrawal
and structured notifications through the existing inbox/email worker. Flutter,
moderator policy, independent organizations, annotations and multiple evaluators
remain outside these releases.

Baseline: develop 9e076d7; original checkout and SAP stash preserved.
Worktree: sap-issue9; Release 1 branch fix/sap-backend-core.

Ruling: native worktree creation cannot locate the moved repository; use a Git
worktree under the writable SMARTEVENT-APP folder. No existing checkout is reset.

Pre-flight: response models must support incomplete drafts and legacy budget rows;
withdrawal consumes the Release 1 aggregate response; notification migration must
precede deployment of Release 2 models. Saved historical evidence is immutable.

## Progress

- Baseline SAP test suite: pending fresh run.
- Information, budget, response schemas: pending.
- Withdrawal, notifications, migration and handoff: pending.
- Final tests, visual PDF verification and independent review: pending.

## Deployment boundary

The connected Supabase project is the application project; no disposable staging
project has been identified. Its migration ledger lists the base SAP migration,
but not the later SAP review/signature/attachment migration. Verify actual schema
and reconcile migration history before any deployment. No live schema or email
changes are authorized merely by running local tests.

- Task 1 complete: baseline 31 passed; information tests RED (500 limit) then GREEN (3 passed). PDF extraction excludes repeating page footers.
- Schema inspection confirms review/attachment tables exist despite absent migration ledger entry; notification payload does not exist.

- Task 2 complete: budget tests RED (extra fields rejected) then GREEN (15 core tests); existing 31 SAP tests passed with new fields. Budget addendum has four columns; totals remain authoritative.

- Task 3 complete: OpenAPI regression RED (empty response schema) then GREEN; 48 SAP/core tests and full backend 469 passed. Existing dependency deprecation warnings remain.
- PDF boundary sample rendered with Poppler and visually checked on pages 4-6: 16 maximum-length budget rows, maximum money, quantity 100000, and 4000 information characters fit across addenda. Sample under ignored tmp/pdfs.
- Ruling: no staging project or local PostgreSQL installation is available. Keep production unchanged; provide opt-in PostgreSQL checks and deployment instructions. Real controlled-recipient email verification remains a deployment gate.

- Task 4 complete: withdrawal tests RED (405, missing endpoint) then GREEN (19 passed). Metadata copies preserve uploader/time and private file references; unsigned review records block withdrawal even with empty notes.
- Task 5 complete: notification tests RED (missing payload) then GREEN; 29 combined follow-up tests passed. CLI generated additive JSONB migration. Three opt-in PostgreSQL tests skip without SAP_TEST_POSTGRES_URL; real lock/migration checks remain unverified.
- User-requested README_SAP_PROGRESS.md created with completed work and remaining deployment/frontend tasks.

- Final verification: entire backend suite 498 passed, 3 PostgreSQL checks skipped,
  187 existing dependency warnings. No test failures.
- Independent review of 9e076d7..2153bf6: no actionable findings. Reviewer checked
  connected API/schema/service/PDF paths, immutable history, transaction boundaries,
  notification delivery, migration and tests; no code changes requested.
- Final ruling on external checks: PostgreSQL runtime locking/migrations, deployed
  access policies, staging and real email delivery are unverified deployment gates.
  SQLite and mocked email results do not certify them. Deploying before those checks
  risks environment-specific failures; draft PRs will state this limitation.
- Remote develop advanced to c741291 during work, but its tree is identical to
  9e076d7. No content integration or additional feature changes are needed.
