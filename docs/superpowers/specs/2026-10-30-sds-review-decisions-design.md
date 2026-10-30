# SAP proposal: department review and SDS decisions

Date: 2026-10-30. Status: approved 2026-10-30.

## Why

A proposal (SAS-SDS-FO-020) goes from the organization straight to the SDS
Office today. The university's process puts the organization's Moderator and
the Department Dean first. The SDS Office can only sign or return; it cannot
reject. The organization never sees what the SDS Office wrote or decided.

## The workflow (approved)

1. The organization fills Parts 1–3 and submits.
2. The Moderator (`adviser` account of that organization) approves or returns.
3. The Dean (`admin` account of that department) approves or returns.
4. The SDS Office fills Part 4, writes remarks, then decides:
   - **Approve**: signs electronically (needs Part 4 saved). Paper slots 5–9
     (SAS Director to University President) follow, as today.
   - **Revise**: back to the organization's draft. It edits and resubmits, and
     goes through the Moderator and Dean again. Signatures already collected
     do not carry over (today's behaviour).
   - **Reject**: final. The proposal locks; nothing can be resubmitted. The
     organization would start a new proposal on a new event.
5. A return by the Moderator or Dean works like Revise.
6. The organization sees the outcome and the SDS remarks in Part 4.
7. The SDS remarks print on the form for all three outcomes. A rejected form
   carries a "Rejected" mark, as the signed form carries its stamp.
8. A rejection notifies the person who submitted the proposal.

## Goals

- The proposal reaches the SDS queue only after the Moderator and Dean approve.
- The SDS Office has three decisions, each confirmed, each with remarks.
- The organization reads the outcome and remarks in Part 4; the printout shows them.
- Part 4 stays the SDS Office's: other accounts see it read-only.

## Non-goals

- No electronic signatures for the Moderator or Dean. Their paper slots (2, 3)
  stay paper, recorded by the SDS Office as today.
- No new notifications for the Moderator or Dean. The existing event approval
  sends none, and this keeps to it.
- No change to slots, the Word template layout, or Part 6 evaluation.

## Anti-goals

- A new look. Every screen uses the app's existing Brut components
  (`BrutScreen`, `BrutHeader`, `BrutFooter`, `BrutButton`, `BrutCard`,
  `BrutBadge`, `BrutInlineMessage`, `SapSdsOnlyNotice`). No new colours,
  fonts, or layouts.
- A second approval system. The Moderator and Dean use the existing
  `/events/{id}/approve` and `/reject` and the existing buttons on the event
  screen.
- Losing remarks. Remarks written before a decision must survive it and print.

## Constraints

- **Branches.** Backend commits go to `feature/backend-setup`. Frontend
  commits go to a new branch `Frontend/SDS-Addition-Setup`. Nothing goes to
  `develop`.
- **`feature/backend-setup` was 29 commits behind `develop`**, which carried
  backend changes it lacked (27 backend files: PRs #20, #22, #24). It was
  fast-forwarded to `develop` before Phase 0.
- **Database.** A new proposal state needs a Supabase migration (the
  `sap_proposals.state` check constraint) and the same change in
  `models_sap.py`.
- **Printout** runs Word on Windows (`services/sap_pdf.py`); tests render real PDFs.
- **Tests.** Backend: pytest from `smartevent-backend/`. App: `flutter test`.
  Each phase ends with both suites passing.

## States

Proposal `state` (new value in bold), with the event `status` beside it:

| Proposal state | Event status | Who acts |
|---|---|---|
| `draft` | `draft` | Organization |
| **`pending_department_review`** | `pending_adviser` | Moderator |
| **`pending_department_review`** | `pending_admin` | Dean |
| `pending_sap_review` | `pending_institutional_review` | SDS Office |
| `revision_requested` | `draft` | Organization |
| `sds_signed` → `approved` → `completed` | as today | SDS Office (paper slots, scan, evaluation) |
| `rejected` | `rejected` | Nobody (final) |

A proposer with the `adviser` role skips the Moderator step and starts at
`pending_admin`, as the existing event approval does.

## Phases

### Phase 0 — land today's fixes

Already written and tested in this worktree, not committed:
- sign refuses a missing Part 4 with a plain message;
- the SDS summary loads on open; saved remarks come back;
- Part 4 text boxes take 5000 characters.

Backend files go to `feature/backend-setup`, app files to
`Frontend/SDS-Addition-Setup`, which starts from `develop`. This design
document goes with the app files.

### Phase 1 — backend: department review stage

- `submit` moves the proposal to `pending_department_review` and the event to
  `pending_adviser` (or `pending_admin` for an adviser proposer). The revision
  snapshot and printout are still made at submit.
- `/events/{id}/approve` and `/reject` accept SAP events in that state:
  - Moderator approve: event → `pending_admin`;
  - Dean approve: proposal → `pending_sap_review`, event →
    `pending_institutional_review`; notify the SDS Office (as submit does today);
  - either return: proposal → `revision_requested` with the remarks, event →
    `draft`, Part 4 cleared, proposer notified.
  - Decisions are recorded with `record_decision`, as for other events.
  - The proposal output says who last returned it (`moderator`, `dean` or
    `sds`) beside `return_remarks`, so the app can name them.
- The SDS Office does not see a proposal before the Dean approves (its event
  list, `GET` access, and notifications).
- The proposer can withdraw during department review as well as SDS review.
- Migration and model constraint gain `pending_department_review`.
- The test helpers that submit a proposal (`populate` in `test_sap.py`, and
  the withdrawal and printout tests) go through the Moderator and Dean.
- Done when: submit → Moderator → Dean → SDS works end to end; each return
  lands in the draft with its remarks; SDS sees nothing early.

### Phase 2 — backend: SDS decisions and remarks

- New `POST /sds-reject` (SDS only, `pending_sap_review` only): overall
  remarks required, section remarks optional; proposal → `rejected`, event →
  `rejected`; proposer notified ("SAP proposal rejected").
- Revise (`/return`) and Reject take the same remarks fields as sign, and
  keep section remarks instead of overwriting them.
- Paper slots 5–9 can be recorded only after the SDS signature; slots 1–4
  as today.
- The printout shows SDS remarks for returned, signed and rejected revisions;
  a rejected one carries a "Rejected by the SDS Office" mark.
- `rejected` is final: every write refuses it (most already check a specific
  state; add tests).
- Done when: the three decisions work, each prints remarks, and a rejected
  proposal accepts no further change.

### Phase 3 — app: what the organization sees

- `SapState` gains `pendingDepartmentReview`; `rejected` becomes real.
- Part 4 for non-SDS accounts: answers read-only, plus an outcome banner
  (Approved / Needs revision / Rejected / With the SDS Office) and the SDS
  remarks, overall and by section — as in the mockup.
- The six-part form hides SDS-only actions from non-SDS accounts.
- A returned proposal shows a banner on the six-part form naming who returned
  it (Moderator, Dean or SDS Office) with their remarks. Part 4 shows only the
  SDS Office's remarks.
- A rejected proposal opens read-only with the rejection banner. Its event
  must not offer "revise and resubmit" the way a plain rejected event does
  (event detail, events hub, and the SDS list's status mapping).
- Done when: an organization account sees outcome and remarks for each state,
  and cannot reach SDS actions.

### Phase 4 — app: review screens

- The SDS review screen offers Approve and sign, Return for revision, and
  Reject, each confirmed. Revise and Reject require overall remarks. The
  separate "Return for revision" button on the six-part form moves here.
- The Moderator and Dean use the existing Approve / Reject on the event
  screen. For a proposal event, the second button reads "Return for
  revision", and they can open the proposal read-only.
- Done when: each role can do exactly its step from the app.

## Calls I made (check these)

- One new proposal state, with the event status telling Moderator from Dean,
  so the existing event screens and labels work unchanged.
- Moderator and Dean "Reject" on a proposal means return, not final reject.
- Only the SDS Office can reject finally.
- Reviewer notifications for Moderator and Dean are out of scope.
- The printout is rendered on request, not stored, for rejected and returned
  revisions; the signed one stays stored as today.
- Phases 1–2 ship before 3–4; the app tolerates the old backend until then.
- `Frontend/SDS-Addition-Setup` branches from `develop`; the design document
  is committed there.
- Each phase is committed and pushed to its branch only after both test
  suites pass, and I report before starting the next phase.

## Settled questions

1. `feature/backend-setup` lacked backend fixes that were on `develop`. Answer:
   merge `develop` into it first. It was strictly behind, so this was a
   fast-forward to 74f2946.
