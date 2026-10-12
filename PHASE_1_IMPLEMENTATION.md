# Phase 1: institutional routing and compliance foundation

Implemented on 4 October 2026; migrations 008 and Phase 1 are now applied to the
configured Supabase project. This is not a finished student-facing module or a
verification of a deployed HTTP server. It supersedes the previous
two-stage event approval contract. Institutional signatories approve **in sequence**,
as confirmed by the project owner.

## Delivered

| Deliverable | Implementation |
|---|---|
| Signatory role | Super Admin provisions an unscoped school account. It can read assigned events/letters only during institutional review and approve/reject its current routing step. |
| Dynamic routing | Admin/Super Admin configures 1–20 distinct, ordered signatories per event. Decisions, timestamps, remarks and review rounds are retained. |
| Participant schema | Event-specific student roster, requirement rules, and individual compliance records; cross-event links and duplicate roster/requirement records are blocked. |
| Requirement presets | Seeded consent, medical clearance and learning-journal definitions, available through a read-only API. |

Existing authentication, mandatory password setup, suspension, organization
isolation, private proposal-file access and the prohibition on self-review remain.
No new production dependencies were added. Existing authorization, account email,
approval history and audit services are reused.

## Workflow and authority

```text
Treasurer/Admin/Super Admin proposal:
Draft -> Adviser review -> Admin review -> Institutional review -> Approved

Adviser proposal (existing exception retained):
Draft -> Admin review -> Institutional review -> Approved

Institutional review:
Signatory 1 -> Signatory 2 -> ... -> final assigned Signatory

Rejection -> edit -> resubmit -> new review round and fresh approvals
```

The API state for institutional review is `pending_institutional_review`.
`EventOut` now includes `review_round`, starting at 1.

- Only Admin/Super Admin can configure routing, within their existing event
  scope. This is allowed in `draft`, legacy `pending`, `pending_adviser`, or
  `pending_admin`. Array order becomes `step_order` starting at 1.
- Signatories must be active, not suspended, and finished with initial password
  setup. These conditions are checked on configuration and again on Admin approval.
- The event proposer cannot be an assigned signatory or review their own event.
- Admin approval now advances to institutional review, **not final approval**.
  Missing/unavailable signatories return HTTP 409; no approval is recorded.
- All current-round assigned signatories may read the proposal while it is in
  institutional review. Only the first still-pending step can approve or reject.
  Later or duplicate decisions return HTTP 409.
- Admin, Super Admin and Adviser cannot bypass or act as an institutional
  signatory. The final assigned signatory's approval sets the event to `approved`.
- A rejection sets the event to `rejected`. Editing/resubmitting follows existing
  owner/administrator rules. Resubmission increments the round, copies the route
  with fresh pending steps, and preserves earlier decisions. The Admin may then
  change the new route before institutional review.
- Routing is frozen during institutional review. If a reviewer becomes unavailable
  at that point, the institution must restore their legitimate account access;
  this phase does not provide emergency reassignment or an approval override.
- Signatory event/file access ends when the event leaves institutional review.
  Previously issued short-lived file links remain usable until their expiry.
  Normal account/profile/password/inbox self-service remains available.
- Existing approved/completed events are not reset or retroactively routed.
  Existing pending proposals need a route before their next Admin approval.

Officers remain operationally read-only. SDS Staff remains a separate proposal-letter
oversight role. Signatories gain no financial, inventory, report, roster, or general
administration access. Event/expense review notifications are not added in this phase.

## API additions

| Method and path | Access / contract |
|---|---|
| `POST /auth/register/signatory` | Super Admin only. `{ "full_name": "Institution Reviewer", "email": "reviewer@example.com", "position": "VPAA" }`. Same temporary-password email/setup as school staff. No organization or department fields. |
| `GET /users/signatories` | Admin/Super Admin. Eligible accounts as `id`, `full_name`, `position`; no email disclosure in the picker. |
| `PUT /events/{event_id}/routing` | Admin/Super Admin. `{ "signatory_ids": ["first-uuid", "second-uuid"] }`. Replaces only the undecided current round. |
| `GET /events/{event_id}/routing` | Authorized event readers. All rounds ordered by `review_round`, then `step_order`. |
| `GET /events/requirement-presets` | Existing operational readers; not SDS/Signatory. Read-only definitions. |

Existing `POST /events/{event_id}/approve` and `/reject` accept Signatories for their
current institutional step; optional body `{ "remarks": "Review notes" }` is unchanged.
The event list/detail, approval history, proposal-letter list/detail, and authenticated
`GET /files` now support the restricted signatory view. Private files still use the
existing authorized short-lived link mechanism, not public object URLs.

## Database

| Table | Purpose and safeguards |
|---|---|
| `document_routing` | Event, round, step, assigned user, status, remarks and decision timestamp. Unique step and signatory within each round. |
| `requirement_presets` | Global definitions. Backend runtime role can read, not change them. |
| `event_participants` | Event-specific student number, name and optional email. Unique student number within an event. Not an authentication account. |
| `event_requirements` | Event document rules, optional preset reference, pre/post phase, required/notarized/sensitive flags. Copies can retain event-specific rules. |
| `student_compliance_records` | One participant/requirement pair. Both must belong to the same event. Default `MISSING`; states `MISSING`, `SUBMITTED`, `VERIFIED`, `REJECTED`. Reviewed states require reviewer and timestamp. |

Seeded definitions:

- `parent_guardian_consent`: pre-activity; notarization required.
- `medical_clearance`: pre-activity; marked sensitive.
- `student_learning_journal`: post-activity.

These are the requested document definitions, **not official CHED form replicas
or a certification of legal compliance**. They are not automatically attached to
every event. Participant/rule management, record creation, uploads and verification
endpoints/UI belong to Phase 2. `CLEARED` will be participant-level clearance, not
a paperwork status. No student login model has been introduced yet.

All five new tables enable RLS and revoke access from `PUBLIC`, `anon`,
`authenticated`, and `service_role`. The server-only `smartevent_app` database role
uses the existing backend policy; FastAPI authorizes the actual end user. Never
give that database role or its credentials to the frontend.

## Deployment order

1. Back up and inspect the intended database. Confirm its existing base schema
   and numbered scripts `001`–`008` are applied, including the hardened server role.
2. Review and apply, as schema owner, the one-time migration
   [20261004005904_phase1_institutional_routing_compliance.sql](supabase/migrations/20261004005904_phase1_institutional_routing_compliance.sql).
   It is transactional and not designed for blind repeat execution.
3. Deploy the backend **after** the schema change. Do not run the new API against
   a database missing `events.review_round` or the new tables.
4. Create institution-approved Signatory accounts and complete their password
   setup. Configure ordered routes for pending proposals.
5. Integrate the frontend changes below and perform staging acceptance tests
   before inviting end users. Live email and file delivery still need acceptance tests.

The new migration was generated using the Supabase CLI. Historical schema scripts
remain in `scripts/`; there is no established CLI migration baseline for them.
Do not blindly use `supabase db push` against an unbaselined project. Record the
migration in the institution's deployment history. Existing role/status checks
are replaced with `NOT VALID` checks to preserve historical rows while enforcing
new writes; audit legacy rows before explicitly validating those checks.

## Frontend integration and next phases

- Add the Signatory role and its restricted event inbox; do not load the general dashboard.
- Add Super Admin account provisioning and Admin ordered-route selection.
- Display the institutional state, current reviewer, step results and review rounds.
  Use `GET /events/{id}/routing` plus the event's current round; enable review only
  for the first pending step belonging to the authenticated Signatory.
- Refresh after a decision. After final approval/rejection, return to the Signatory
  inbox because event detail is no longer accessible to that account.
- Show missing-route and unavailable-reviewer errors; do not offer a bypass.
- Update the end-user presentation/PDF before testing this new workflow. The earlier
  guide/PDF is a pre-Phase-1 snapshot, not evidence that the new UI exists.

Phase 2 remains: logistics/transport records, PIC ratio validation, participant and
requirement management, student upload access, bulk physical verification and LGU
documents. Phase 3 remains: QR boarding, completion, post-activity and alternatives.
Phase 4 remains: verified CHED annex exports and approved retention automation.

## Verification

`.venv\Scripts\python.exe -m pytest -q -p no:cacheprovider app`:
**342 passed**, with four pre-existing warnings. Coverage includes sequential/out-of-order
decisions, no administrator bypass, self-review, cross-organization denial,
rejection/resubmission history, signatory account readiness and restricted file access.

The checked-in `scripts/verify_phase1_migration.mjs` passed against an isolated
PGlite PostgreSQL engine: SQL execution, preservation of existing approved events,
three preset rows, constraints, RLS, denied client CRUD and allowed server CRUD.
It uses a minimal pre-Phase-1 schema, not a full production database clone, and
does not test concurrent connections or Supabase Storage. To rerun:

```powershell
npm install --prefix tmp/phase1-postgres --no-save --package-lock=false --ignore-scripts @electric-sql/pglite@0.5.8
node scripts/verify_phase1_migration.mjs
```

PGlite is a temporary development verification tool, not an application dependency.
The original implementation checks did not change the live database. The following
authorized deployment subsequently applied the migrations; no users were created,
emails sent, or files uploaded during verification.

## Live deployment verification — 4 October 2026

Target: **SMARTEVENT: APP**, Supabase project `vzdctweadahekptsmnyn`, matching the
backend's configured database and Storage URL. Applied 008 first, verified its
security setup, then applied Phase 1. Each migration used a 5-second lock timeout
and 45-second statement timeout; SQL behavior otherwise matches the saved files.

| Local source | Recorded remote migration version | Result |
|---|---|---|
| `scripts/008_security_hardening.sql` | `20261004072642`, `security_hardening_008` | Applied |
| `supabase/migrations/20261004005904_phase1_institutional_routing_compliance.sql` | `20261004072724`, `phase1_institutional_routing_compliance` | Applied |

Supabase's migration tool assigned the remote versions above. Do not reapply the
older local Phase 1 timestamp: CLI migration history still needs deliberate
alignment/baselining before adopting `db push`. Historical scripts 001–007 were
not replayed or falsely marked as applied in migration history.

Verified against the live database:

- All five Phase 1 tables exist with RLS enabled; all three presets are seeded.
- All 17 pre-existing public tables now have RLS and the backend policy.
- Client roles have no direct public-table grants. `smartevent_app` has SELECT
  but no INSERT/UPDATE/DELETE privileges on the preset definitions.
- Both document buckets are private, limited to 10 MB and the configured file types.
  Previously public receipt URLs no longer provide public file access.
- Existing event status counts remain 3 draft, 10 approved, 3 rejected and 3
  pending adviser. All 19 events start at review round 1. The user count remains 11.
- The Supabase security advisor returned no findings. Performance-only notices
  remain: [19 uncovered foreign keys](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys)
  (including the two composite compliance foreign keys) and
  [30 unused indexes](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).
  No unrelated index creation/deletion was performed.

The real local FastAPI app was exercised through its ASGI test client against
the live PostgreSQL database, with normal JWT authentication and no dependency
overrides. All test transactions were read-only. Short-lived diagnostic tokens
were generated in memory for existing ready accounts and never printed or saved.

| `GET /events/requirement-presets` | Result |
|---|---|
| Super Admin, Admin, Adviser, Treasurer | HTTP 200; exactly the three seeded presets |
| SDS Staff | HTTP 403 |
| No token | HTTP 401 |

Officer and Signatory were not exercised live because no eligible accounts of
those roles were available to this check. This verifies the local route against
the migrated database, not Flutter screens or an independently deployed server.

Repeat with `.venv\Scripts\python.exe -m scripts.verify_requirement_presets_live`.

Remaining production setup: the configured backend database connection still uses
the `postgres` owner account. The new `smartevent_app` role is NOLOGIN and has not
been assigned to a dedicated server login; the management connection cannot
`SET ROLE smartevent_app`. A dedicated runtime login/membership and credentials
rollout is a separate operation, not performed here. The advisor's clean result
does not certify this runtime-credential setup or the whole application's security.
