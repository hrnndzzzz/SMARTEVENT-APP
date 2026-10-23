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
