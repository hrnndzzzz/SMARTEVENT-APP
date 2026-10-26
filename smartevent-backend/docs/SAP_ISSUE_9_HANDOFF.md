# Issue #9: backend release contract

## Release 1: form data and responses

No database migration is needed. `additional_information` accepts 0–4000
characters in draft writes and submission. The string shape and heading parsing
are unchanged. Flutter still enforces 500 until its separate update ships.

Budget writes use `PUT /events/{event_id}/sap-proposal/budget-items`:

```json
{
  "expected_version": 3,
  "items": [{"particulars": "Snacks", "quantity": 150,
             "unit_cost": "10.00", "amount": "1500.00"}]
}
```

`quantity` must be a JSON integer from 1 to 100000 (default 1).
`unit_cost` is optional/null, nonnegative money with at most 12 digits and two
decimal places. Send money as decimal strings. `amount` is authoritative: the
server does not calculate it from quantity/cost. The sum of amounts must equal
`details.total_budget` at submission. Existing rows remain valid; reading old
rows does not backfill their missing keys. Newly saved rows include defaults.

The budget addendum prints Particulars, Quantity, Unit cost (PHP), and Amount
(PHP); absent unit cost prints blank. Long additional information uses addenda.

All SAP JSON operations now describe their success responses in OpenAPI,
including workflow, attachments, signed download links and public verification.
The PDF operation describes binary `application/pdf`. OpenAPI availability still
follows the existing environment configuration.

Aggregate example (identifiers and timestamps are illustrative):

```json
{
  "id": "00000000-0000-0000-0000-000000000001",
  "event_id": "00000000-0000-0000-0000-000000000002",
  "state": "draft", "version": 4, "revision_no": 0,
  "return_remarks": null, "form_code": "SAS-SDS-FO-020", "form_version": "001",
  "details": {"title": "Welcome activity", "total_budget": "1500.00"},
  "clearance": null,
  "collections": {
    "program-flow": [],
    "budget-items": [{"particulars": "Snacks", "quantity": 150,
                      "unit_cost": "10.00", "amount": "1500.00"}],
    "support-requests": [], "affected-classes": []
  },
  "attachments": [], "sds_review": null, "evaluation": null
}
```

Draft `details` may be `{}`. Do not read collections at the top level or replace
hyphens with underscores. On 409, reload before retrying. The client must update
its information limit and budget editing/parsing separately; backend deployment
alone does not change those controls.

## Release 2: withdrawal

`POST /events/{event_id}/sap-proposal/withdraw` accepts
`{"expected_version": 9}` and returns the same aggregate as other SAP writes.
Only the original proposer with an existing authorized proposer role can call it.
It requires `pending_sap_review` and no current SDS review record (even an empty
notes record), signed review, or recorded physical checkpoint. A state conflict
or stale version returns 409; wrong owner/role/scope returns 403.

On success, `state` and event status become `draft`, `version` increments, and
`revision_no` is retained. SDS clearance is cleared. Submitted evidence stays
immutable. Attachments appear in the next working revision with new attachment
IDs but the same private file, original uploader and upload timestamp; historical
attachment IDs remain accessible under the existing scoped download rules.

Reload after success. Edit via existing draft operations, have SDS reconfirm
clearance, then resubmit to create a new revision with fresh checkpoints. For the
current editable PDF preview use `GET .../pdf?draft=true`; a numbered PDF request
still refers to that submitted revision. A 409 means reload and show the current
state; never retry blindly. After review starts, use the existing SDS return path.

## Release 2: notifications

`GET /notifications` and the read response add nullable `payload`. Example:

```json
{
  "event_id": "00000000-0000-0000-0000-000000000002",
  "proposal_id": "00000000-0000-0000-0000-000000000001",
  "revision_no": 1,
  "state": "draft",
  "action": "sap_withdrawn"
}
```

Existing records and non-SAP notifications may have null payloads. Use `event_id`
to load the current SAP proposal and handle missing/inaccessible proposals through
the normal API checks. The payload records the state at notification creation;
the current proposal may have progressed. Never treat it as authorization.

Recipients remain the proposer and active, unsuspended SDS staff. Inbox records
are committed with workflow changes. The existing email worker handles pending
and failed records with stable per-notification idempotency keys; already-sent
records are not resent. SDS signing is distinct from final approval. No push
delivery or historical-notification replay is added.

## Migration, rollout and rollback

1. Merge/deploy Release 1 first. It needs no database migration. Then integrate
   the frontend form changes against its contract.
2. Confirm all prior SAP migrations are reflected in the target schema and
   migration ledger. On the inspected application project, the review/attachment
   tables exist but their migration is absent from the ledger. Reconcile that
   discrepancy before using a bulk migration push; do not recreate existing tables.
3. Apply `20261023134616_sap_notification_payload.sql` in staging. It adds one
   nullable JSONB column without changing rows, grants or policies. Deploy
   Release 2 backend only after this succeeds.
4. Run the full backend suite, PostgreSQL tests, existing `supabase/tests/sap_access.sql`
   checks and live scoped API checks. Verify inbox and email using agreed test
   accounts/recipients before enabling the worker in a deployed environment.
5. Deploy Release 2 and its frontend integration. Monitor 422 validation failures,
   409 workflow conflicts, response serialization errors, and pending/failed email
   counts. For an application rollback, retain the nullable payload column and
   roll back code; do not delete notifications, revisions, or attachment rows.

The implementation session has not deployed either release, applied a live
migration, or sent real emails. Only the application Supabase project was found;
no staging database was provisioned. Set `SAP_TEST_POSTGRES_URL` to a disposable
database with a name ending in `_test` to execute the migration/lock tests:

```powershell
python -m pytest app/test_sap_postgres.py -q
```

These tests use unique scratch schemas, never fall back to `DATABASE_URL`, and
remove only their own schemas. They verify both winners of a concurrent
withdrawal/review race and that adding the payload preserves existing rows and
table access configuration. A skip does not establish PostgreSQL correctness.

## Release checks

Run `python -m pytest app -q -p no:cacheprovider` with isolated test settings.
Review generated PDFs at 4000 characters and with maximum-length budget rows.
Verify draft/save/reload/submit/PDF against a staging API before frontend release.

Existing documentation predates some SDS signing changes. Current OpenAPI,
the SAP frontend implementation handoff, and this release contract supersede
older statements that SAP has only 13 operations or no electronic SDS signing.
