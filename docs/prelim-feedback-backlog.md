# Prelim feedback: what was asked for, and where it stands

Two sources, written down 22 Oct 2026 so nothing is lost between now and
the demonstration.

1. **The capstone moderator**, in `SYSTEM_CHECKING_PRELIM` (22 Sep 2026).
   Scored 81: Functionality 25/40, UI-UX 6/10, Dashboard 20/20,
   Views 20/20, Teamwork 10/10. Eighteen numbered enhancements.
2. **Our own review of the app**, 22 Oct. Roughly twenty changes, mostly
   UI-UX — the category that lost the most proportionally.

Status is one of **done**, **in progress**, **todo**, or **blocked**
(waiting on the backend). Priority is for the demonstration deadline:
**P1** must be in the video, **P2** should be, **P3** after.

**Re-checked 27 Oct 2026.** A lot had shipped since this was written and
the list understated it — D1 to D6, E3, E4, B2, G13 and G15 were all
marked todo and are built. More importantly F10 to F13 are no longer
blocked: the states they needed now exist. Statuses below marked *(27
Oct)* were confirmed against the code that day, not re-walked on the
phone unless it says so.

---

## A. The demo and roles

| # | What | Status | P |
|---|---|---|---|
| A1 | Hold the heading → "Access demo mode?", start as officer | **done** | P1 |
| A2 | Role picker in Settings: officer, treasurer, adviser, SDS, admin, super admin | **done** | P1 |
| A3 | Demo works more than once per launch | **done** | P1 |
| A4 | SDS role can reach the proposals it reviews — today it lands on an empty Proposal letters screen | **done** | **P1** |
| A5 | Adviser role likewise | **done** | **P1** |

A4 and A5 are what stand between us and filming the flow end to end.

## B. Dashboard

| # | What | Status | P |
|---|---|---|---|
| B1 | Event status says *which* stage: with the moderator, with SDS, and the rest | **done** | P1 |
| B2 | "SmartEvent" wordmark clickable → dashboard; on the dashboard, an easter egg (screen pulses blue/green) | **done** *(27 Oct)* | P3 |
| B3 | "THU / OCT 22" larger, clearer, clickable → event planner | **done** | P2 |
| B4 | "CITE · TREASURER" likewise → account info | **done** | P2 |
| B5 | Notification button: the **bell** shakes, not the square; a new notice fills the box red, pulsing once | **done** | P2 |
| B6 | Account avatar has square corners showing inside the circle — also on Edit profile | **done** | P2 |
| B7 | Floating scan button overlaps the budget row *(found on device; spun off separately)* | **done** *(30 Oct)* — docked to the navigation bar instead of floating; a test measures it against every dashboard figure | P2 |

## C. Money

| # | What | Status | P |
|---|---|---|---|
| C1 | Allocated / spent / left / pending as separate boxes in a grid | **done** | P2 |
| C2 | Colour-coded green / amber / red by how close to the limit | **done** | P2 |
| C3 | Consider renaming spent and left to inflow and outflow | **declined** — they mean different things; see G12 for the real feature | P3 |
| C4 | Pending is clickable → expenses | **done** | P2 |
| C5 | Record an expense: drop the receipt and document features, full crosshair, faint grid lines | **done** | P2 |
| C6 | Every category list needs a "create category" | **done** | P2 |
| C7 | Inventory: it is not clear how an item is created — from a receipt, or by hand? Decide and make it obvious | **waiting on you** — not yet tested | P2 |

## D. Financial reports

| # | What | Status | P |
|---|---|---|---|
| D1 | Download becomes an icon button, bottom right, like the scan button | **done** *(27 Oct)* | P2 |
| D2 | It opens a window showing the dashboard snapshot | **done** *(27 Oct)* | P2 |
| D3 | PDF / CSV / print-ready as separate squared boxes | **done** *(27 Oct)* | P2 |
| D4 | Four charts in a grid, each full screen and clickable for detail | **done** *(27 Oct)* | P2 |
| D5 | Period, scope and org-analytics buttons in the same layout, each opening a window | **done** *(27 Oct)* | P2 |
| D6 | Every window gets its own buttons | **done** *(27 Oct)* | P2 |

## E. Elsewhere

| # | What | Status | P |
|---|---|---|---|
| E1 | Flagged: sort by severity, date, priority | todo | P3 |
| E2 | Proposal letters: upload button gets the D1 treatment | todo | P3 |
| E3 | Search covers everything, and a search or a question lands you where you need to be | **done** *(27 Oct)* — events, transactions, categories, inventory and screens | P2 |
| E4 | Floating menu: the orange marker gradients — filled on the outer edge, gradient on the inner, both sides gradient in the middle | **done** *(27 Oct)* | P2 |

## F. Creating an event

Our professor called this cluttered. The largest piece of work on the list.

| # | What | Status | P |
|---|---|---|---|
| F1 | A starting screen before Part 1, with the La Consolacion header (ACPES form as reference) | todo | P2 |
| F2 | Date of proposal filled in automatically | **done** *(30 Oct)* — seen on the phone, filled from the activity date | P2 |
| F3 | Off-campus agreement surfaced there too | **done** *(30 Oct)* — Part 1 offers the setting and the acknowledgement, and Save refuses without one | P2 |
| F4 | Group the fields by kind and colour-code them: identity (title, org, school year), timing (date, start, end), and so on | todo | P2 |
| F5 | Support step: smaller square tiles in a grid | todo | P2 |
| F6 | Breakdown step: reorder | todo | P3 |
| F7 | Two back buttons — remove one | **done** *(30 Oct)* — Parts 1-3 and 5 already had one; Parts 4 and 6 still carried both. A test counts them | P2 |
| F8 | The top back button asks: save as draft, cancel, go back | **done** *(30 Oct)* — verified on the phone, all three choices | P2 |
| F9 | Steps swipeable between activity, support and breakdown | todo | P3 |
| F10 | No new event while one is pending | **todo** — never needed the backend; it is a guard on the events already loaded | P2 |
| F11 | Concluded events show a waiting-for-evaluation screen (Part 6) | **todo** — `completed` and the evaluation route both exist now | P3 |
| F12 | A rejected event is editable against the marks, and resubmitted | **done** *(31 Oct)* — editing and resubmitting already worked; the marks did not show. The hub now leads with what the SDS Office wrote | P2 |
| F13 | A `resubmitted` status, and events tagged as resubmissions | **todo** — no such state, but `revision_no` above 1 already says it | P3 |

F10–F13 were blocked when this was written. They are not any more. The
SAP state list is now `draft, pending_sap_review, revision_requested,
sds_signed, approved, completed, rejected`, a submit bumps `revision_no`,
and withdrawal returns a proposal to draft — which is everything these
four needed. F10 never needed the backend at all.

## G. The moderator's eighteen

Where they are not already covered above.

| # | What | Status |
|---|---|---|
| G1 | End-user consultation, documented | not ours |
| G2 | Identify the super administrator and its permissions | todo |
| G3 | Organizational administrator hierarchy | todo |
| G4 | Confirm whether officers are view-only | todo |
| G5 | Validate the UI with end users and adviser | not ours |
| G6 | Registration confirmation and automatic admission | todo |
| G7 | Printable and downloadable dashboard reports | **done** — D1–D3 are built |
| G8 | A financial report per event | **nearly done, unreachable** *(27 Oct)* — the backend route, `ReportsService.eventReport` / `exportEvent` and `AppState.loadEventReport` all exist; no screen opens any of them. It needs a screen and a button, not a feature |
| G9 | Consolidated reports weekly, monthly, by school year | todo |
| G10 | Receipt similarity detection, with stated criteria | todo |
| G11 | A purpose on every receipt, tied to an event | todo |
| G12 | Source of funds: registration, donation, sponsorship | todo |
| G13 | Inventory records linked to the event they are for | **done** *(27 Oct)* — items carry an event and the list badges "No event link" |
| G14 | Classify inventory transactions: acquisition, purchase, other | todo |
| G15 | Inventory updated only after a purchase completes | **done** *(27 Oct)* — purchase completion creates the item as an unconfirmed draft |
| G16 | Reports split by department and organisation, with filters | todo |
| G17 | A school year on every event record | partly — Part 1 asks for it |
| G18 | Financial reports by school year and semester | todo |

---

## What this adds up to

**Re-counted 27 Oct, one week from the deadline.**

Everything in A, B and C is done except B7, and D and E are done except
E1 and E2. What is genuinely left is F, the create-event rework our
professor called cluttered, and the untouched half of the moderator's
eighteen.

Left, in the order worth doing it:

1. ~~F7, F8, F2, F3~~ — **done 30 Oct.** Three of the four were
   already built and only recorded as todo; F7 was half done, with
   Parts 4 and 6 still carrying two back buttons.
2. ~~F12~~ — **done 31 Oct.** Worth filming: the SDS Office returns
   Industry Immersion Talk with a reason, and the proposer opens it to
   find that reason at the top of the six parts.
3. **F1, F4, F5** — the visual rework of the form. Real work. Do it only
   if the four above are finished.
4. **G8** — cheaper than it looks and worth promoting. Everything
   under it is built; it needs a screen that shows what
   `loadEventReport` already returns and a button on the event to open
   it. Then **G9, G16, G18** — consolidated, by department and
   organisation, by school year and semester — which are additive and
   genuinely unstarted.
5. **G10, G11, G12, G14** — receipt similarity criteria, a purpose on
   every receipt, source of funds, inventory classification.
6. **G2, G3, G4, G6** — decisions and documentation rather than code.

Not worth starting this week: F6, F9, E1, E2, F11, F13.

The honest read: the demonstration can be filmed today. The list above
is what would make it score better, not what makes it work.
