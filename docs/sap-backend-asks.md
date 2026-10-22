# SAP proposal: what the app now does, and what the backend still needs

For hrnndzzzz. Written 21 Oct 2026, against the SAS-SDS-FO-020 (001)
slice as the frontend contract describes it.

The front end is finished and green against that contract. Everything
below is a gap found by filling the real paper form, not a redesign
request.

**Updated 21 Oct 2026, after `73a23b0` (SAP Changes Added).** That change
landed SDS review, signing, attachments, PDF generation against the real
V.3 form, and off-campus support. None of asks 1-3 moved, and the app
has since gained two more, 8 and 9, from the flow notes the adviser
gave us. Asks 8 and 9 are the ones to read first if you only read two.

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

Ordered by how much they block us. 1-3 and 8-9 are blocking; 4-7 and
10 are not. 8 and 9 are new and come from the flow notes, not the paper form.

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

### 8. A review stage between the proposer and the SDS Office

The flow notes say the proposed budget has to be **reviewed by the
Moderator/Dean before the officer goes to Finance and SDS**. We read
"Moderator" as the existing adviser role, which should keep this small.

There is nowhere to put it. The states are:

```
draft -> pending_sap_review -> sds_signed -> approved -> completed
         (+ revision_requested, rejected)
```

Nothing sits between the proposer and the SDS Office, so a proposal
waiting on its moderator is indistinguishable from one nobody has
touched. "Moderator" and "Dean" exist in the app today only as
*signatory labels* in Part 5 — names printed on the paper — not as an
approval gate.

**Ask:** a state before `pending_sap_review`, reachable by the proposer
and clearable by the adviser, with the usual return-for-changes path.
Name it whatever fits; `pending_adviser_review` is what we would guess.

If this is more than a small change, say so and we will keep Part 2
submitting straight to the SDS Office in the meantime — we would rather
know than build against a stage that is not coming.

### 9. `department` and `department_type` should accept null

The flow notes ask for **no department on the form**, with independent
organisations in mind: an org that belongs to no department at all.

Both are required and non-empty today:

```python
department_type: str = Field(min_length=1, max_length=80)
department:      str = Field(min_length=1, max_length=100)
```

We have already taken the two inputs off the screen and now send the
account's own values instead, so nothing is broken right now and this
is **not urgent**. But an organisation with no department has nothing
to send, and the server would reject it.

**Ask:** make both nullable, whenever independent orgs become real.

### 10. A route to withdraw a submitted proposal

The proposer can submit, and the SDS Office can return. There is nothing
between: once sent, a proposal cannot be taken back by the person who
sent it. The events API has `submit`, `approve`, `reject` and `delete`,
and `delete` is not the same thing — it throws the work away.

Our adviser asked for a plain cancel: the proposer realises something is
wrong, takes it back, fixes it, sends it again.

**Ask:** a route that moves a pending proposal back to `draft` for its
own proposer, refused once anyone has decided on it. Something like
`POST /events/{id}/withdraw`.

Refusing after a decision matters: if it were allowed after a return,
withdrawing would erase the remarks the office had just written.

The app has this working against local state and tells a real session
plainly that the route does not exist, rather than appearing to do
nothing.

---

## 3. What is already proven working

So you know what not to re-check:

- `GET /events/{id}/sap-proposal` -> 404 before creation
- `POST` -> 201, row lands in Supabase with `state = draft` and
  `form = SAS-SDS-FO-020/001`
- All 13 endpoints wired, including the 409 path: on version conflict
  we reload and never retry blind
- Money stays a decimal string end to end, no float anywhere
- `off_campus` was rejected by the original slice, so the app still
  offers on-campus and online only. `73a23b0` added it server side; the
  client has not caught up yet. Not an ask — ours to do.
