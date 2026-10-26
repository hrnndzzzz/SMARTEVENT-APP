# Implementation ledger — plan: docs/offline-viewing.md

- Base: c741291 (origin/develop), isolated branch feat/offline-viewing.
- Task 1: implemented and verified — SQLite snapshots, scoped private files,
  offline filtering, reopen, invalidation and obsolete-file removal.
- Task 2: implemented and verified — cached startup, expired-token viewer,
  guarded writes, scope/account/server invalidation, GET-only foreground
  preparation, pagination, three-request limit, restart and foreground resume.
- Task 3: implemented and verified — persistent status, per-area saved dates,
  cached images/documents/PDFs, disabled write controls and read-only SAP.
- Task 4: independent review completed; all findings addressed with regression
  tests. Final full-suite, analysis and Android build are running after the
  last startup and navigation changes.

## Review evidence

The first reviewer session was interrupted before its final report. A fresh
reviewer resumed the single final review, inspected the diff and backend routes,
and returned the remaining findings. No second review was dispatched after fixes.

- Scope-change late response: failing test reproduced old-scope data reaching
  the caller; API/session generations now invalidate it. Regression passed.
- Explicit file denial: failing test reproduced retained private bytes; both
  metadata and bytes are now evicted. Regression passed.
- Foreground resume: failing test reproduced a dropped restart while old HTTP
  requests drained; a pending rerun now resumes automatically. Regression passed.
- Viewed financial filters: failing test reproduced a missing matching PDF;
  preparation now refreshes the JSON and PDF together. Regression passed.
- Freshness: promoted from minor because the agreed scope needs per-area dates;
  a widget regression failed before the saved-date dialog and passed afterward.
- Additional boundary tests cover online mutation during partial preparation,
  password-setup denial, visible records after denied refresh, immediate cached
  startup, and closing previous-account navigation on logout.
- The last full suite before the final startup/navigation changes passed 470
  tests with 5 skipped. The subsequent startup/session/navigation group passed
  all 8 tests using the secure-storage package's official in-memory test store.
- Android APK builds succeeded before the final startup/navigation changes.

## Rulings and validation boundaries

- Ruling: ordinary Git worktree used because the desktop tool could not resolve
  the chat's deleted original checkout. Existing worktrees were untouched;
  this checkout must be managed through Git rather than managed-worktree cleanup.
- Ruling: signatory workflows and account-administration caching remain excluded,
  as agreed. Those features do not gain offline capabilities in this change.
- Ruling: no local projection added for event-filtered movement queries because
  no current UI uses that query. A future filtered caller must download its exact
  response or add a projection before claiming offline support.
- Ruling: password-change-required responses revoke an older cached viewer;
  requiring online password setup is preferable to restoring revoked access.
- Ruling: physical airplane-mode/restart and iOS validation remain unverified on
  this host. Automated tests and an Android build do not substitute for device QA.
- Deferred review minors: none; freshness was promoted and fixed.


## Final verification — 2026-10-24

- flutter test --no-pub: 473 passed, 5 skipped, exit 0.
- flutter analyze --no-pub: 0 errors, 4 unused-import warnings, 149 informational
  lints; exit 1 because lint findings remain. This is not a clean analysis pass.
- flutter build apk --debug --no-pub: succeeded, exit 0.
- git diff --check: passed.
- APK: build/app/outputs/flutter-apk/app-debug.apk.
- No backend migration, deployment, push or merge was performed.
- Physical device airplane-mode/restart checks and iOS compilation were not run.
