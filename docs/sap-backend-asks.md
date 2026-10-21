# SAP proposal: what the app now does, and what the backend still needs

For hrnndzzzz. Written 21 Oct 2026, against the SAS-SDS-FO-020 (001)
slice as the frontend contract describes it.

The front end is finished and green against that contract. Everything
below is a gap found by filling the real paper form, not a redesign
request.

---

## 1. The flow as the app now does it

Creating an event *is* filling in the form. There is no separate
create-event screen any more, and no menu of parts.

```
[+ New event]
     |
     v
Part 1  Activity details      ------ on "Next: school support":
     |                               POST /events            (draft, submit_now = false)
     |                               POST /events/{id}/sap-proposal
     |                               PUT  .../details
     |                               PUT  .../program-flow
     v
Part 2  School support        ------ PUT .../support-requests
     |
     v
Part 3  Additional info +     ------ PUT .../additional-info
        budget breakdown              PUT .../budget-items
     |                               POST .../submit
     v
  pending_review  -> the SDS Office (Parts 4-6)
```

Three things follow from this that differ from the old client:

- **The event record is created on the way out of Part 1**, from Part 1's
  own title and date. Nothing is POSTed until there is a title and a
  date, so no empty events.
- **Parts 4, 5 and 6 are not steps for a proposer.** The progress bar
  shows Activity / Support / Breakdown only. Once `state` leaves
  `draft`, the app shows a read-only status screen instead of the form.
- **Organisation is taken from the account, not picked per event.** See
  ask 7.

---

## 2. The asks

Ordered by how much they block us. 1-3 are blocking; 4-7 are not.

### 1. `additional_information` max_length 500 is too small

Part 3 of the real form is ten separate headings, not one note. The app
composes them into the single `additional_information` field:

> Attendance monitoring, Focus, Attire, Guest speaker coordination,
> Class interruption notice, Educational continuity, Certificates or
> credits, Registration process, Target audience, Documentation and
> media coverage

The two real filled forms we have (ACPES and JPSSITE) run about **1,500
characters** across those ten. The app currently shows the user a
warning and refuses to save past 500, which means a real proposal cannot
be filled in.

**Ask:** raise `max_length` to 4000, or drop it. 2000 would be tight.

Better still, if you'd rather keep it structured: ten nullable text
columns, or a `additional_information: {heading: text}` JSON object. We
compose and re-parse by heading either way, so either shape works for
us — the limit is the blocker, not the shape.

### 2. Budget breakdown needs a QUANTITY column

The schema has `particulars` + `amount`. The JPSSITE form's breakdown
reads:

| Particulars | Quantity | Unit cost | Amount |
|---|---|---|---|
| Snacks | 150 | 10.00 | 1,500.00 |

We cannot represent that. Right now we flatten it into the particulars
string, which means the printed form does not match the paper and the
SDS Office cannot check the arithmetic.

**Ask:** add `quantity` (int, ge 1, default 1) and `unit_cost` (decimal
string, nullable) to `budget-items`. Keep `amount` as the authoritative
total so nothing existing breaks — treat quantity/unit_cost as what the
row shows, and `amount` as what it sums to.

### 3. `response_model` on the SAP routes

The SAP routes declare no response schema, so `/openapi.json` says
nothing about what comes back. That is how we shipped a bug that cost a
day: the collections come back nested under a `collections` key with
**hyphenated** names (`budget-items`, `support-requests`,
`program-flow`), and our parser looked for them at the top level. Every
list parsed as empty. Saved work silently vanished on reload, and
nothing failed loudly enough to notice.

**Ask:** put `response_model=` on all 13 SAP routes. We generate against
the OpenAPI document; without it we are guessing from example payloads.

### 4. An annotations table (the green pen)

Our adviser asked for the post-submission marks to be digital. On the
signed ACPES copy these are green-pen checkmarks against individual
rows, plus handwritten notes in the margin under a signatory's name.

The app has this working against local state already — three kinds of
mark, anchored to a field. It needs somewhere to live.

**Ask:** a table, roughly:

| column | type | note |
|---|---|---|
| `id` | uuid | |
| `proposal_id` | uuid | FK |
| `anchor` | text | which field or row the mark is on |
| `author` | uuid | FK users |
| `author_role` | text | role at time of writing, not looked up later |
| `kind` | enum | `checked` / `note` / `change` |
| `text` | text | nullable for `checked` |
| `resolved` | bool | |
| `created_at`, `updated_at` | timestamptz | |

Who may write one: adviser, SDS staff and signatories. Proposers read
them and resolve them.

`author_role` is stored rather than joined on purpose — a note written
by someone who was treasurer last year should still read as a
treasurer's note.

### 5. Notification payload and wording for SAP

There is no notification when a proposal changes hands. The one the
adviser specifically asked for is **"SDS has approved"** reaching the
proposer.

**Ask:** fire a notification on each `state` transition, with a payload
that names the proposal and the new state so we can deep-link to it.
Wording for the three that matter to a proposer:

- `draft -> pending_review` — "Sent to the SDS Office."
- `-> approved` — "The SDS Office has approved <activity>."
- `-> returned` (if that state exists) — "<activity> was returned for changes."

### 6. Part 6: one evaluator or several?

The contract reads as single-evaluator — one `outcome`, one `remarks`,
one `evaluated_by`. Chris believed it routed to several. Worth settling
before either of us builds for the wrong one; we have built single.

### 7. `/auth/me` should return organisation and department *names*

It returns ids. Only Admin and Super Admin may call `/organizations`, so
an officer or a treasurer **cannot resolve their own organisation's
name** — they have the id and no way to turn it into text.

The form needs the name printed on it, and we decided organisation is a
fact about the account rather than a per-event choice. So right now an
officer has to type their own org name by hand, which is exactly the
sort of thing that ends up misspelled on a university document.

**Ask:** include `organization_name` and `department_name` on
`/auth/me`. Not a new endpoint and no permission change — the user
already has the ids, this just saves them a lookup they are not allowed
to do.

---

## 3. What is already proven working

So you know what not to re-check:

- `GET /events/{id}/sap-proposal` -> 404 before creation
- `POST` -> 201, row lands in Supabase with `state = draft` and
  `form = SAS-SDS-FO-020/001`
- All 13 endpoints wired, including the 409 path: on version conflict
  we reload and never retry blind
- Money stays a decimal string end to end, no float anywhere
- `off_campus` is rejected by this slice, so the app only offers
  on-campus and online
