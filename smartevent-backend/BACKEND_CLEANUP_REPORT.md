# Backend cleanup report

Date: 2026-10-08

## Summary

What this repo does: SMARTEVENT supplies the mobile app's authentication,
organization-scoped event approvals, compliance, attendance, finance, inventory,
and reporting API. This cleanup assumes the existing institutional application
and its current workflows; it does not redesign them or certify production load.

The cleanup preserved production behavior, database migrations, API routes,
test cases, credentials, and existing uncommitted work.

## Review scope

- Inventoried backend application, scripts, migration files, documentation,
  dependencies, generated output, and temporary directories.
- Parsed all 79 first-party Python files in `app/` and `scripts/` (12,138 lines
  before cleanup) for syntax and unused-import candidates.
- Scanned production top-level undecorated functions for references and compared
  multi-statement function bodies for exact duplicates. Neither scan identified
  a production deletion candidate. These are conservative static checks, not
  proof that all code is reachable or that no duplication remains.
- Inspected application startup, shared authorization/token handling, selected
  service and route paths, CLI utilities, and test fixture registration.
- Checked diagnostic-script references in documentation before retaining them.

This was a clutter-focused review, not a line-by-line security audit of all
12,138 lines or a fresh audit of SQL migrations and external services.

## Changes made

| Area | Cleanup |
|---|---|
| Five test modules | Removed seven unused imported names: `issue_password_reset_otp`, two `uuid4` imports, `create_access_token`, `timedelta`, `EventComplianceDocument`, and `get_current_user`. |
| `requirements-dev.txt` | Removed the duplicate `httpx` pin; the same version remains supplied by `-r requirements.txt`. No installed package was removed. |
| `.gitignore` | Replaced two narrow temporary-directory rules with `tmp/`, covering local SDKs, migration-test dependencies, preview files, and runtime logs. Files remain on disk. |
| Generated caches | Deleted 102 files totaling 1,870,801 bytes (about 1.78 MiB) from five cache directories. |

Deleted cache directories: `app/__pycache__`, `app/routers/__pycache__`,
`app/services/__pycache__`, `scripts/__pycache__`, and `.pytest_cache`.
Deletion was restricted to validated paths under the backend, rejecting filesystem
links. These disposable files were not archived; Python and pytest regenerate them.

Pytest fixture imports were retained even when ordinary static name-use checks
flagged them. Removing them would break fixture discovery.

## Deliberately retained

- Every production router, service, schema, model, and security check: no safely
  removable production code was established.
- Migration history, schema-repair scripts, and historical backfill utilities.
- Account bootstrap, email diagnostics, live-readiness checks, migration tests,
  and the attendance PDF preview script. Standalone tools are not dead code just
  because the application does not import them.
- Existing guides, generated PDFs, local virtual environment, Flutter SDK,
  migration-test dependencies, and active-process logs.
- All frontend files and the large inspection export outside the backend.

## Verification

- All 79 Python files parse successfully after cleanup.
- No remaining unused-import candidates after accounting for fixture parameters.
- `python -B -m pip check`: no broken requirements found.
- `git check-ignore`: temporary logs, previews, and the local Flutter SDK match
  the new ignore rule.
- Initial completed regression run: **390 passed, 1 failed, 4 warnings**.
  The failing authentication-bootstrap test passed on its isolated rerun.
- Final full-suite result: **391 passed, 4 warnings in 29.45 seconds** using
  `python -B -m pytest app -q -p no:cacheprovider`.

The first sandboxed pytest invocation stalled before producing test results and
was stopped. Completed test runs used the existing local Python environment
outside that sandbox. Tests used isolated SQLite fixtures and mocked delivery;
no live account provisioning, migration, email, or storage operation was run.

## Finding resolved in follow-up

1. **SQLite UUID conversion can make regression tests intermittent.** The failed
   bootstrap-login test encountered a numeric value while SQLAlchemy expected a
   UUID string. A separate in-memory reproduction confirmed that the PostgreSQL
   UUID type compiles as `UUID` in SQLite and a numeric-only 32-character value
   is stored as `real`. SQLite's numeric conversion can therefore lose the text
   needed by the UUID decoder. This is independent of unused-import removal.
   Follow-up fix on 2026-10-08: `app/conftest.py` now compiles UUID columns as
   `CHAR(32)` only for SQLite tests. PostgreSQL still compiles to native `UUID`;
   no production model or migration changed. Three deterministic OTP round-trip
   cases cover leading zeros, long numeric IDs, and scientific-notation-like IDs.
   All three failed before the fix with incorrect SQLite storage types.
   After the fix, the full backend suite passed: **394 passed, 4 warnings in
   34.75 seconds**. An offline dialect compilation check also confirmed that
   PostgreSQL retains its native UUID type.

## Token usage

An exact per-turn input/output/total token counter is not exposed to this task.
Tool-output token estimates are not the total conversation usage. No exact token
count or billing estimate is claimed.

## Verdict and limits

The verified clutter was removed conservatively, following Ponytail's rule to
preserve functionality and avoid speculative refactoring. No dependencies or
features were removed, and no new runtime dependency was added.

Not checked: authenticated Android workflows, live database/storage/email/OCR,
deployment performance, third-party SDK internals, and exhaustive security review.
The identified SQLite UUID instability is addressed by the follow-up fix;
dependency deprecation warnings remain.
