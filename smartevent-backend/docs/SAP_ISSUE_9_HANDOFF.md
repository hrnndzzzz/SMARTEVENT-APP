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

## Release checks

Run `python -m pytest app -q -p no:cacheprovider` with isolated test settings.
Review generated PDFs at 4000 characters and with maximum-length budget rows.
Verify draft/save/reload/submit/PDF against a staging API before frontend release.

Existing documentation predates some SDS signing changes. Current OpenAPI,
the SAP frontend implementation handoff, and this release contract supersede
older statements that SAP has only 13 operations or no electronic SDS signing.
