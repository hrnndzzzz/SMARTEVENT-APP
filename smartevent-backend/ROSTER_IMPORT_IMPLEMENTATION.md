# Excel roster import implementation record

Plan source: the approved Excel Roster Import Implementation Plan in this chat.

## Decisions

- Include Full Name: the approved five-column proposal accidentally omitted this required field in the existing roster schema. The correction was disclosed before implementation.
- Work in the user-selected Copy backend on its existing feature/backend-setup branch. Preserve existing files; do not merge, push, or deploy.
- Use data_only=False instead of the plan's data_only=True so formula cells are rejected explicitly rather than accepted as stale cached data. Users must paste results as plain text.
- Bound XLSX decompression and worksheet traversal in addition to the 5 MiB/1,000 member limits to keep small compressed files from causing unbounded resource consumption. Documented additional limits may require cleaning unusually large workbooks.
- Use the existing real database test fixture and a focused service. No new roster table, import queue, file retention, frontend changes, or account creation.
- Scoped name resolution considers only records the importing Admin may use; Super Admin name resolution covers all departments and organizations.

## Progress

- Baseline: 394 existing tests passed before production changes.
- New endpoint test failed as expected with HTTP 405 before implementation.
- Parser, schemas, endpoint, dependency pins, and guide implemented.
- Initial verification: 27 import tests passed, including atomic rollback on injected database conflict.
- Final verification: `python -m pytest -q` — 421 passed, four pre-existing dependency deprecation warnings. `git diff --check` passed.
- Independent read-only review: no critical or important findings.
- Minor coverage follow-ups deferred: explicit cross-department scenario (same-department cross-organization is covered); successful exactly-1,000-member batch; direct macro, ZIP expansion, and worksheet scan-limit tests.
- Live PostgreSQL concurrency and deployed configuration were not tested. Database-conflict rollback is tested against an isolated SQLite session. Frontend integration remains outside this backend task.
