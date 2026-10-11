# Financial Management — backend changes and frontend handoff

This phase implements the adviser's financial recommendations in the backend.
It builds on the existing Core System Features reports and exports. No Flutter
screens, live database migrations, or live storage uploads were performed.

## Adviser recommendation coverage

| Recommendation | Backend implementation |
| --- | --- |
| Individual financial report for each event | `/reports/event/{event_id}` contains actual income, expenses, budgets, net balance, fund-source breakdown, and linked receipt records. |
| Weekly, monthly, school-year consolidated reports | `/reports/financial` and its export endpoints support all three periods. Weekly/monthly use actual financial transaction dates. |
| School-year and semester financial reports | Academic periods filter by the event's recorded school year and semester; these are required for the relevant report types. |
| Separate departmental/organizational events | `event_scope=departmental` or `organizational` filters the same report dataset and exports. Organization/department authorization is always enforced. |
| Specific actual sources of funds | Income retains a descriptive `source`, adds an explicit `source_type`, and reports group eligible received income by both values. |
| Duplicate/similar receipt mechanism | Exact duplicates are blocked; similar receipts are persisted with flags and require independent review. Criteria are specified below. |
| Receipt purpose/description required | Receipt `purpose` cannot be blank. Legacy expense receipt entry uses the transaction's required description as the recorded purpose. |
| Every receipt linked to event and transaction | Receipt links to exactly one expense or income and derives its event and ownership from that transaction. Unassigned expenses cannot acquire receipts. |

## What changed

- New `receipts` table and authenticated receipt API, with purpose, merchant,
  reference number, actual date/amount, transaction ownership, file hash,
  similarity flags, reviewer, decision, explanation, and timestamps.
- Income supports `registration_fees`, `sponsorship`, `donation`, and `other`.
  Existing descriptive source names remain intact; legacy records default to
  `other` rather than guessing their financial classification.
- Event and consolidated reports now include `income_by_source`,
  `withheld_income_total`, and `withheld_income_count`. Event reports also include
  `receipts`. Income responses expose `receipt_review_status`.
- Monetary inputs use decimal validation: positive amounts, at most two decimal
  places, and a NUMERIC(12,2)-compatible size. Blank descriptions/sources/purposes
  are rejected. Totals use decimal arithmetic before JSON numeric serialization.
- Existing expense creation, URL attachment, upload, and OCR pathways now use
  receipt validation. A receipt URL cannot bypass duplicate checks by entering it
  through an older expense endpoint.
- Receipt-bearing expenses cannot change event, amount, or expense date, detach
  their receipt, or be deleted. Reject a pending expense instead of deleting its
  financial evidence. Reviewed receipt evidence is immutable through the API.
- Approval locks expense, category, and event rows so concurrent approval budget
  checks use serialized balances in PostgreSQL. Existing budget-deduction
  triggers remain responsible for actual deductions; they are not replaced.
- PDF/CSV/HTML exports include source summaries and receipt-review information.

## Duplicate and similarity policy

Checks operate within the same organization, across its events and across both
income and expense receipts. Matching documents in unrelated organizations do
not reveal one another's records. One receipt record is allowed per transaction.

### Exact duplicates: 409, not saved

Any of the following is an exact match:

1. Same canonical receipt URL: scheme/host are case-insensitive, path is retained,
   and query strings/fragments are ignored. This detects changing signed tokens
   on the same file URL. Query-based document identifiers must use distinct paths
   or the receipt upload endpoint; query-only differences are intentionally not
   considered separate documents.
2. Same SHA-256 of raw uploaded file bytes. The backend computes the hash; clients
   cannot submit a trusted hash. Applies to registered receipt uploads and the
   older expense upload endpoint, not pre-transaction OCR scan uploads.
3. Same normalized merchant plus receipt/reference number. Normalization uses
   Unicode NFKC, case folding, and collapsed whitespace. Reference numbers are
   treated as unique for that merchant within the organization; reused numbering
   requires administrative investigation, not a casual duplicate override.

Database unique constraints provide a final check on concurrently inserted
receipt records. Existing unimported expense receipt URLs are also checked.
Creating a financial transaction with a nested duplicate receipt fails the whole
request; it does not leave a committed extra income/expense entry.

### Similar receipts: persisted flag and review

Normalized merchant matches, amount matches exactly to the cent, and actual
receipt dates are within one day. A different receipt number does not suppress
this warning. Receipt responses include `is_flagged=true`, matching authorized
`similar_receipt_ids`, and `review_status=pending`.

- Pending/rejected receipt review blocks expense approval.
- Income with pending/rejected receipt review remains visible in the income
  ledger but is excluded from report totals/source summaries. Its amount/count
  is explicitly disclosed as withheld.
- Adviser/Admin/Super Admin may independently clear or reject the flag with a
  recorded explanation (minimum 10 characters). The receipt recorder cannot
  review their own evidence. Review decisions are audited.
- Clearing releases the income into totals and allows ordinary expense approval.
  Rejecting continues to withhold income and blocks approval. A pending expense
  can then be rejected through the existing expense workflow.
- Rewriting pending receipt metadata cannot silently remove its original flag.
  Cleared/rejected evidence cannot subsequently be overwritten through the API.
- Receipt flags are separate from the existing expense OCR-amount mismatch flag;
  a later OCR result cannot clear a receipt duplicate/similarity flag.

These checks are fraud-prevention signals, not proof of fraud. Merchant metadata
must be supplied or extracted/reviewed through the expense OCR flow. Different
photos/crops of a receipt are not matched perceptually. A reuploaded pre-transaction
scan with a new URL and no identifying merchant/reference metadata may not be
matched. Do not present this feature as infallible duplicate detection.

## Frontend API integration

Use `Authorization: Bearer <token>` on every financial/report/receipt request.
Officer is read-only; Treasurer/Admin/Super Admin record finances; Adviser/Admin/
Super Admin review receipts and expenses. Existing organization scope and
self-review restrictions remain active. SDS has no operational financial access.

### Record actual received funds

`POST /incomes`:

```json
{
  "event_id":"event-uuid",
  "source_type":"sponsorship",
  "source":"ACME Company",
  "purpose":"Venue sponsorship for leadership seminar",
  "amount":"2500.00",
  "received_on":"2026-09-20",
  "receipt":{
    "receipt_url":"https://example.com/receipts/sponsor-001.jpg",
    "purpose":"Acknowledgment of venue sponsorship",
    "merchant":"ACME Company",
    "receipt_number":"ACK-001",
    "issued_on":"2026-09-20"
  }
}
```

Nested `receipt` is optional: not every actual financial transaction has a
receipt image at entry time. If provided, `purpose` and HTTP(S) `receipt_url` are
required. Amount/date default to the transaction's actual values if omitted;
explicit receipt amount must match its linked transaction amount. The returned
income status tells the frontend whether receipt review is holding it from totals.

`POST /expenses` supports the same optional `receipt` object. Expense description
is still required. Older `receipt_url` clients continue to work, but the transaction
must now have an event. If both old URL and nested receipt are supplied, they must
match. When no receipt exists, an unassigned expense can still be recorded; its
legacy consolidated-report treatment is explained below.

### Attach receipt metadata after entering a transaction

`POST /receipts`:

```json
{
  "expense_id":"expense-uuid",
  "receipt_url":"https://example.com/receipts/expense-001.jpg",
  "purpose":"Purchase of seminar supplies",
  "merchant":"School Store",
  "receipt_number":"OR-001",
  "issued_on":"2026-09-20",
  "amount":"500.00"
}
```

Use `income_id` instead of `expense_id` for income. Supplying neither or both
returns 422. The server derives event/organization/department; the client cannot
choose a conflicting assignment. Treasurer attaches to their own transactions;
administrators can manage authorized transactions. It returns a `ReceiptOut`.

Other endpoints:

- `GET /receipts?event_id=...&flagged_only=true&review_status=pending` — scoped inbox.
- `GET /receipts/{receipt_id}` — scoped receipt details.
- `POST /receipts/{receipt_id}/upload` — multipart `file`, supported image type,
  maximum 10MB. Replaces the URL for an editable receipt, computes trusted hash,
  and reruns matching. Upload before review; reviewed evidence is immutable.
- `POST /receipts/{receipt_id}/review` — independent reviewer submits:

  ```json
  {"decision":"cleared","reason":"Original receipts verified as separate purchases."}
  ```

  Or use `decision=rejected`. No generic exact-duplicate override is offered.

Common errors: 400 invalid image, 403 role/scope/self-review denial, 404 unknown
record, 409 duplicate/conflict/immutable evidence, 422 incomplete/invalid input.
Exact-match responses may include the authorized matching receipt ID. Existing
storage availability errors are 502/503. A failed DB write after upload can leave
an unreferenced storage object; review storage cleanup separately.

### Reports and exports

- `/reports/event/{event_id}`: all event income/expense entries, eligible totals,
  source summaries, withheld amounts, and receipt records.
- `/reports/financial?period=weekly&reference_date=2026-09-23`: Monday–Sunday.
- `/reports/financial?period=monthly&reference_date=2026-09-23`: calendar month.
- `/reports/financial?period=school_year&school_year=2026-2027`.
- `/reports/financial?period=semester&school_year=2026-2027&semester=1st`.
- Append `event_scope=departmental` or `organizational` to categorize reports.

Weekly/monthly use `IncomeRecord.received_on` and `Expense.expense_date`, not
event creation date. Academic periods use event academic labels and include all
recorded transactions associated with matching events; no semester start/end
calendar is inferred. Net balance is eligible received income minus approved
expenses, not remaining allocated budget. Pending/rejected expenses are visible
in event detail but do not count as spending.

Legacy event-less approved expenses are separately included in unfiltered weekly/
monthly totals as `unassigned_expense_total`. Academic/scope-filtered reports
cannot classify them and exclude them. Fix historical assignments from actual
records before relying on fully classified reporting.

Source summary response example:

```json
{
  "income_by_source":[
    {"source_type":"sponsorship","source":"ACME Company","income_count":1,"total_income":2500.0}
  ],
  "withheld_income_total":0.0,
  "withheld_income_count":0
}
```

Display withheld values separately instead of presenting them as spendable funds.
Event reports contain every recorded income entry with its receipt review status.
The reports are not substitutes for checking original financial evidence.

Existing exports remain `/reports/event/{event_id}/export?format=pdf|csv|html`,
`/reports/financial/export?period=...&format=...`, and `/reports/financial.pdf`.
Reuse `/analytics/dashboard/exports` discovery and the byte-download/printing
instructions in `CORE_SYSTEM_FEATURES.md`.

## Deployment and legacy data

1. Back up and test on staging. Apply migrations 001–005 first, then
   `scripts/006_financial_management.sql`. It creates receipt constraints, private
   RLS-protected receipt storage metadata, source classification, transaction-link
   checks, and immutable financial-link guards. The backend requires its trusted
   database connection; no public Supabase receipt-table policies are created.
2. Old incomes retain their actual `source`; review `source_type=other` if more
   precise classification is needed. Do not create estimated donations/sponsors.
3. Find receipt-bearing expenses without events, blank purposes/descriptions,
   invalid amounts, duplicate historical documents, and incomplete event ownership.
   Correct them from original documents before validating the migration checks.
4. Preview legacy expense receipt import:

   ```powershell
   .venv\Scripts\python.exe -m scripts.backfill_receipts --actor-email "super-admin@example.com"
   ```

   Default mode performs validation in rollback-only transactions. It sends no
   emails and uploads no files. It prints record IDs and eligibility/problems.
   Run with `--apply` only after reviewing staging results. The importer uses
   actual existing URLs, descriptions, OCR metadata, amounts, and dates; it does
   not invent receipt numbers. It retains the original recorder and audits import.
   Blocked rows need manual correction; none are silently discarded.
5. Historical approved expenses are not automatically reversed when an imported
   receipt is flagged. Investigate the original approvals and financial records;
   changing already approved money requires a separately designed correction flow.
6. After data repair, run the constraint validation statements at the end of
   migration 006. Keep original documents and an audit trail for manual corrections.
7. Reuse the existing Supabase image-storage configuration. The existing storage
   service returns public URLs; protected API access does not by itself make an
   already public storage object private. Private buckets/signed file delivery
   require a separate storage-access change before handling confidential receipts.

## Acceptance tests

1. Run `.venv\Scripts\python.exe -m pytest -q -p no:cacheprovider app`.
   Current result: **156 passed**, including 24 new financial test cases.
2. Record actual incomes from each fund type. Confirm source names, date, purpose,
   event, and amounts appear in event/source reports. Blank fields, negative/NaN
   values, and amounts with more than two decimal places must be rejected.
3. Create approved and pending expenses. Compare event totals against original
   records; only approved expenses count toward spending.
4. Put known transactions inside/outside a test week/month. Confirm reporting
   uses financial dates. Test school year, semester, and both event classifications.
5. Register a receipt, then reuse its URL (including changed query token), uploaded
   bytes, or normalized merchant/reference on another transaction: expect 409.
6. Register different receipts with same merchant/amount and adjacent dates:
   expect a persisted similarity flag. Expense approval must be blocked; matching
   income must appear in the ledger but be withheld from totals.
7. As an independent reviewer, clear with a documented reason; totals/approval
   become eligible. Separately reject a similar receipt and confirm it stays held.
   Try self-review, a blank reason, and rewriting metadata to remove the flag.
8. Try changing event/amount/date, detaching a receipt, or deleting its expense.
   Confirm no receipt-to-transaction linkage is broken.
9. Read/download as Officer; writes must remain blocked. Try a foreign organization
   receipt and SDS access: 403. Check PDF/CSV/HTML source and review information.
10. Validate SQL constraints, simultaneous receipt submissions and budget approvals,
    actual storage, and legacy import on staging PostgreSQL before deployment.

Automated tests use isolated SQLite and mocked storage. They do not validate live
PostgreSQL triggers/locks, production storage permissions, or original receipts.
No inventory workflow changes are introduced in this financial phase.
