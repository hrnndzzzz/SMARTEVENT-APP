# Organization hierarchy and permissions implementation

Implement the user-approved hierarchy on `feature/backend-setup`, using the existing role and position fields.

1. Add route regressions for qualifying Officer positions, owner-only event lifecycle and letters, Treasurer-only recording, department-wide Admin scope, and live position changes.
2. Add shared capability checks; restrict Officer write exceptions to event and proposal-letter routes; retain existing review stages and scope rules.
3. Restrict every financial recording route to Treasurer, preserving viewing and independent review.
4. Expand Admin scope to its department; retain organization assignment as the default for creation, and validate requested organizations. Cover roster, accounts, reports and audit queries.
5. Expose effective position capabilities through `/auth/permissions`; update policy documentation, fixtures and superseded regression expectations.
6. Run focused tests and the complete isolated backend suite; review the complete diff.

No new roles, database migration, account reassignment, Flutter authentication integration, or live-service changes are required. Adviser and Moderator both use `adviser`. Only President, Vice President and Secretary extend the `officer` role with proposal permissions; all other Officer writes remain denied.

## Delivery notes

- Implemented in the isolated `organization-permissions` checkout on the existing `feature/backend-setup` branch. Native worktree creation could not resolve the moved main checkout, so Git created the worktree; the app cannot attach this unmanaged checkout. Use its explicit path.
- Existing Admin organization assignments remain creation defaults; account transfers still require Super Admin. Admin permissions now span the assigned department without automatic data reassignment.
- Offline historical-receipt maintenance remains separate from Treasurer-only financial-module APIs. Live PostgreSQL triggers, storage, OCR and corrupted legacy ownership were not verified or changed.
- Independent review found missing resulting-position data on unclaimed roster audits; this is fixed and covered by a regression.
- Referenced draft deletion now rolls back and returns HTTP 409, preserving linked records rather than exposing a database error.
- Verification used the existing Python environment read-only, a test-only JWT key, and isolated SQLite fixtures. The full suite passes: **243 tests**, with four existing dependency deprecation warnings. No dependency or schema changes are required.
- Publication to `feature/backend-setup` is requested. Preserve the remote branch's existing SAP workflows and authentication protections when integrating these permission changes, then verify the combined backend before pushing.
- Remote integration retains Signatory accounts, institutional routing, pre-activity readiness, private file signing, and authentication protections. Qualifying Officers use the same owner-only checks for SAP Parts 1–3 and submission; SDS-only stages remain restricted. Dean roster imports now accept any organization in the assigned department.
- Publication verification after remote integration: **502 backend tests passed**, with 106 existing-library deprecation warnings, including PDF rendering warnings. A fresh independent review found no critical, important, or minor issues. Frontend files match the remote branch; live database/storage deployment remains unverified.
