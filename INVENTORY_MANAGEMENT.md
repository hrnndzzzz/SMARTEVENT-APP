# Inventory Management — backend handoff

This phase addresses the adviser's remaining Inventory Management recommendations.
The backend was changed; no live SQL migration, stock adjustment, or Flutter edit
was performed. Apply migration 007 after migrations 001–006 before deploying this
backend version against Supabase.

## Recommendation coverage

| Adviser recommendation | Implementation |
| --- | --- |
| Link all inventory records to their events | New catalog items require an initial/intended event. Every new stock movement also requires the actual usage/receipt event. Links must belong to the same organization and department as the item. Legacy missing links are explicitly discoverable and repairable. |
| Classify every inventory transaction | Typed opening balances, acquisition, donation, purchase, issue, return, disposal, and adjustment. Each movement has a nonblank reason, event, actor, quantity, and timestamp. |
| Add purchased items only after completed purchase and complete details | Approval no longer adds stock. A separate completion action requires an approved expense, linked receipt, full payment details, delivery confirmation, vendor, and explicit asset quantities/units. It records stock and ledger entries atomically and prevents duplicate receipt of the same purchase. |

## Purchase workflow (important behavior change)

1. Treasurer/Admin records an event-linked expense with asset line items and its
   purpose-bearing receipt. Each line can record quantity and unit. The line's
   `amount` is its financial line total, not an automatically multiplied unit price.
2. An independent Adviser/Admin/Super Admin approves the expense through the
   existing review endpoint. Asset expenses without a registered receipt cannot
   be approved. Receipt similarity reviews must be resolved as before.
3. Approval affects financial status and the existing budget triggers only.
   **It does not create inventory or increase quantities.**
4. Once full payment and actual delivery are complete, the Treasurer who recorded
   the expense, or an authorized Admin/Super Admin, submits completion details.
5. The server receives the asset quantities into stock and creates one `purchase`
   movement for every asset expense line. Movement links include event and
   `expense_item_id`; the line's `converted_inventory_id` traces its catalog item.
6. A newly created catalog item is a draft requiring administrator confirmation
   before issue/return/disposal or other manual movements. Its received quantity
   is already recorded; catalog confirmation does not add the quantity again.
7. Existing catalog items are reused only when ownership and units match. A second
   completion attempt returns 409 and never adds stock again.

Asset purchase completion does not deduct budgets again. Existing financial reports
continue counting approved expenses according to their established policy;
purchase completion is a stock-receipt control, not a replacement financial ledger.
Consumable expense lines remain financial records and are not automatically added
to stock. Physical stock acquired without purchase uses typed manual movements.

## Frontend contracts

Use `Authorization: Bearer <token>`. Catalog creation/update/deletion and draft
confirmation remain Admin/Super Admin only. Adviser/Treasurer/Admin/Super Admin
can perform authorized manual movements. Officer remains read-only. SDS has no
operational inventory access.

### Create an event-linked catalog item

`POST /inventory`:

```json
{
  "event_id":"event-uuid",
  "item_name":"Folding chair",
  "quantity":10,
  "unit":"pcs",
  "initial_transaction_type":"opening_balance",
  "reason":"Verified existing chairs assigned to seminar",
  "low_stock_threshold":2,
  "location":"Organization storage"
}
```

Organization-scoped admins inherit their organization/department. Super Admin
supplies both IDs. `event_id` is required, even for a zero-stock catalog item.
Positive starting stock produces a corresponding opening movement in the same
commit. Valid initial types are `opening_balance`, `acquisition`, or `donation`;
`purchase` cannot be used to bypass the completed-purchase workflow.

Opening/acquisition/donation entry is for existing or non-purchased stock, not an
alternative way to label an incomplete commercial purchase. Zero-stock catalog
entries are not received stock and do not increase any stock balance.

### Stock movements

`POST /inventory/{inventory_id}/transactions`:

```json
{
  "event_id":"event-uuid",
  "transaction_type":"issue",
  "change_qty":-3,
  "reason":"Issued three chairs for seminar"
}
```

| Type | Quantity rule | Use |
| --- | --- | --- |
| `opening_balance` | Positive | Initial verified stock on catalog creation only |
| `acquisition` | Positive | Received existing/non-purchase assets |
| `donation` | Positive | Actual donated stock |
| `purchase` | Positive | Generated only by completed purchase; generic movement API rejects it |
| `issue` | Negative | Stock issued for a specific event |
| `return` | Positive | Stock returned from that same event |
| `disposal` | Negative | Damaged/lost/retired stock, with reason |
| `adjustment` | Nonzero, either sign | Documented physical-count correction, not an undocumented purchase |
| `legacy` | Historical only | Existing rows awaiting verified classification |

Zero quantity and wrong direction return 422. Insufficient stock, excessive
returns, unconfirmed drafts, or missing legacy event links return 409. A return
cannot exceed that item's outstanding issues for the same event. Stock updates
and movement entries occur in one transaction, with row locking to serialize
competing stock changes in PostgreSQL.

An item's initial event identifies its original intended use/provenance. Reusable
items can be issued or returned for other authorized events through their movement
records. The initial event is not replaced every time an item is reused.

### Complete an approved purchase

Get asset line UUIDs from `GET /expenses/{expense_id}/items`, then:

`POST /expenses/{expense_id}/complete-purchase`:

```json
{
  "paid_on":"2026-09-20",
  "received_on":"2026-09-21",
  "paid_amount":"1500.00",
  "payment_method":"cash",
  "payment_reference":"OR-PAY-1001",
  "vendor":"School Equipment Supplier",
  "items":[
    {"expense_item_id":"asset-line-uuid","quantity":3,"unit":"pcs"}
  ]
}
```

Required conditions:

- Expense is approved, scoped, and not already completed.
- A registered expense receipt has a purpose and matches event/amount. Pending or
  rejected similarity review blocks completion. A legacy bare receipt URL alone
  is not a substitute for a registered receipt record.
- Full paid amount matches the expense total. Vendor, payment method, payment
  reference, payment date, and received date are present. Allowed methods: `cash`,
  `bank_transfer`, `card`, `other`. Completed dates cannot be in the future.
- Every asset line is explicitly confirmed exactly once, without foreign lines;
  quantities are positive integers and units are nonblank. Confirmation is
  required even if an earlier line defaulted to quantity 1.
- Existing catalog units match; quantities are not guessed from OCR or silently
  converted between boxes/pieces. Asset line totals cannot exceed the paid total.

Returns the updated `ExpenseOut`, including `purchase_completed_at`, `paid_on`,
`received_on`, `paid_amount`, `payment_method`, `payment_reference`, and
`purchase_vendor`. Expense items include confirmed `quantity`, `unit`, and
`converted_inventory_id`. The inventory transaction output exposes
`transaction_type` and `expense_item_id`.

Common failures: 403 role/scope/owner denial, 409 incomplete/unapproved/already
completed/legacy conversion, 422 missing details, invalid dates/amount/unit/item
confirmation. Frontend should treat 409 as a workflow message, not retry an action
blindly. Purchases remain absent from stock until this request succeeds.

The backend verifies recorded evidence and authorized confirmation; it does not
independently confirm a bank transfer or a physical delivery with an outside service.

### Queries and legacy repair

- `GET /inventory?event_id=...` — items initially assigned to or moved for an event.
- `GET /inventory?is_draft=true` — catalog review queue.
- `GET /inventory?missing_event=true` — legacy catalog items missing initial links.
- `GET /inventory/{inventory_id}/transactions?event_id=...` — event-specific ledger.
- `PATCH /inventory/{inventory_id}` with `{"event_id":"verified-event-uuid"}` —
  Admin fills a missing initial event. Existing recorded initial links are immutable.
- `PATCH /inventory/{inventory_id}/transactions/{transaction_id}/metadata` — Admin
  repairs an incomplete legacy movement with verified `event_id`,
  `transaction_type`, and `reason`. It does not change or replay `change_qty`.
  Recorded events and purchase provenance cannot be overwritten by this action.
  It cannot classify a row as a completed purchase without purchase evidence.

Catalog PATCH explicitly rejects direct quantity edits. Unit changes are blocked
when stock or movement history exists. Items with quantity, movement history, or
purchase provenance cannot be deleted. Retire real stock using a reason-bearing
disposal movement instead. Create/update/repair/confirmation/completion actions
are audited within their transaction.

## Migration 007 and historical reconciliation

1. Take the manual Supabase backup discussed earlier. Apply/test migrations 001–006
   first, then `scripts/007_inventory_management.sql` on staging.
2. Migration 007 adds event links, line quantities/units, typed ledger metadata,
   purchase completion evidence, unique purchase-line protection, and database
   event/purchase guards. It does not delete records or reset stock. It creates
   missing triggers without `DROP TRIGGER` commands.
3. Existing inventory event IDs remain null until verified; old movement types
   become `legacy`. Existing line quantities use a compatibility default of 1,
   not a claim that the original purchase definitely contained one item.
4. Assign catalog items to actual intended events using the admin repair PATCH.
   Classify historical movements and their event associations from actual records.
   These metadata repairs leave current stock unchanged.
5. Earlier backend versions converted approved assets immediately, sometimes with
   no ledger entry for newly created items. Existing `converted_inventory_id`
   records are retained, and completion rejects those lines to prevent duplicate
   stock. Do not invent payment/delivery dates or replay purchases to make the new
   completion fields look populated. Reconcile historic totals with physical stock
   and original financial records under a reviewed correction procedure.
6. NOT VALID constraints preserve legacy rows but enforce new/updated rows.
   Therefore fill required event metadata before other updates to legacy items.
   Invalid legacy quantities/ownership or unreconstructable purchase provenance
   may need a reviewed database correction; the API does not fabricate them.
7. Validate the constraints and optional NOT NULL statements commented at the end
   of migration 007 only after completing actual historical cleanup. Fully
   classified historical reporting depends on that cleanup.
8. Staging verification must exercise purchase triggers, stock races, and repeat
   completion against PostgreSQL. The automated test database is SQLite and does
   not execute these PostgreSQL guards.

## Step-by-step acceptance tests

1. Run `.venv\Scripts\python.exe -m pytest -q -p no:cacheprovider app`.
2. As Admin, create inventory with event and positive opening quantity. Confirm one
   opening ledger entry, its type/event, and unchanged starting balance. Omit an
   event or try an initial `purchase` type: 422.
3. As Treasurer/Adviser, issue stock for an authorized event, then return part/all.
   Verify quantities and history. Over-return, zero movement, wrong signs,
   over-withdrawal, blank reason, and missing type/event must be blocked.
4. Try a foreign organization's event/item, Officer write, and SDS read: 403.
5. Create an asset expense, with receipt, line amount, quantity, and unit. Approve
   independently. Stock must not change and no catalog row should be created yet.
6. Complete payment/delivery with the payload above. Verify confirmed stock,
   payment fields, purchase ledger type, line provenance, event link, and audit.
7. Repeat completion: 409 with no second stock increase. Try underpayment, missing
   receipt, future dates, unknown/duplicate asset lines, different units, or an
   unapproved expense; stock must remain unchanged.
8. Complete a purchase of a new item. Confirm it appears as draft with received
   quantity and purchase history. Manual movement is blocked until Admin confirms;
   draft confirmation must not increase stock again.
9. Try a generic manual `purchase` movement, direct quantity PATCH, unit changes
   with history, or deleting purchased stock; verify the bypass is blocked.
10. Repair a test legacy item/event and movement classification. Verify audit logs
    and unchanged quantity. Try completing an already-converted legacy purchase;
    verify it cannot duplicate historical stock.
11. Repeat purchase/issue/return cases through the frontend once its team connects
    these endpoints, then test concurrency and migration behavior on staging.

The inventory tests use isolated records and do not write to Supabase or Storage.
No actual payment, delivery, or stock reconciliation was performed by this agent.
