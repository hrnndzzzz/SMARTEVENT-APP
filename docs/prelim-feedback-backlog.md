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
| B2 | "SmartEvent" wordmark clickable → dashboard; on the dashboard, an easter egg (screen pulses blue/green) | todo | P3 |
| B3 | "THU / OCT 22" larger, clearer, clickable → event planner | **done** | P2 |
| B4 | "CITE · TREASURER" likewise → account info | **done** | P2 |
| B5 | Notification button: the **bell** shakes, not the square; a new notice fills the box red, pulsing once | **done** | P2 |
| B6 | Account avatar has square corners showing inside the circle — also on Edit profile | **done** | P2 |
| B7 | Floating scan button overlaps the budget row *(found on device; spun off separately)* | in progress | P2 |

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
| D1 | Download becomes an icon button, bottom right, like the scan button | todo | P2 |
| D2 | It opens a window showing the dashboard snapshot | todo | P2 |
| D3 | PDF / CSV / print-ready as separate squared boxes | todo | P2 |
| D4 | Four charts in a grid, each full screen and clickable for detail | todo | P2 |
| D5 | Period, scope and org-analytics buttons in the same layout, each opening a window | todo | P2 |
| D6 | Every window gets its own buttons | todo | P2 |

## E. Elsewhere

| # | What | Status | P |
|---|---|---|---|
| E1 | Flagged: sort by severity, date, priority | todo | P3 |
| E2 | Proposal letters: upload button gets the D1 treatment | todo | P3 |
| E3 | Search covers everything, and a search or a question lands you where you need to be | todo | P2 |
| E4 | Floating menu: the orange marker gradients — filled on the outer edge, gradient on the inner, both sides gradient in the middle | todo | P2 |

## F. Creating an event

Our professor called this cluttered. The largest piece of work on the list.

| # | What | Status | P |
|---|---|---|---|
| F1 | A starting screen before Part 1, with the La Consolacion header (ACPES form as reference) | todo | P2 |
| F2 | Date of proposal filled in automatically | todo | P2 |
| F3 | Off-campus agreement surfaced there too | todo | P2 |
| F4 | Group the fields by kind and colour-code them: identity (title, org, school year), timing (date, start, end), and so on | todo | P2 |
| F5 | Support step: smaller square tiles in a grid | todo | P2 |
| F6 | Breakdown step: reorder | todo | P3 |
| F7 | Two back buttons — remove one | todo | P2 |
| F8 | The top back button asks: save as draft, cancel, go back | todo | P2 |
| F9 | Steps swipeable between activity, support and breakdown | todo | P3 |
| F10 | No new event while one is pending | **blocked** | P3 |
| F11 | Concluded events show a waiting-for-evaluation screen (Part 6) | **blocked** | P3 |
| F12 | A rejected event is editable against the marks, and resubmitted | **blocked** | P3 |
| F13 | A `resubmitted` status, and events tagged as resubmissions | **blocked** | P3 |

F10–F13 need states the backend does not have. They are in
`docs/sap-backend-asks.md` and in hrnndzzzz/SMARTEVENT-APP#9.

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
| G7 | Printable and downloadable dashboard reports | partly — D1–D3 |
| G8 | A financial report per event | todo |
| G9 | Consolidated reports weekly, monthly, by school year | todo |
| G10 | Receipt similarity detection, with stated criteria | todo |
| G11 | A purpose on every receipt, tied to an event | todo |
| G12 | Source of funds: registration, donation, sponsorship | todo |
| G13 | Inventory records linked to the event they are for | todo |
| G14 | Classify inventory transactions: acquisition, purchase, other | todo |
| G15 | Inventory updated only after a purchase completes | todo |
| G16 | Reports split by department and organisation, with filters | todo |
| G17 | A school year on every event record | partly — Part 1 asks for it |
| G18 | Financial reports by school year and semester | todo |

---

## What this adds up to

Twenty-three of our own items, eighteen of the moderator's, with overlap.
That is days of work, not hours. For the demonstration the order is:

1. **A4 and A5** — without them the roles cannot be filmed.
2. **B1** — the status detail, which is the dashboard's weakest point and
   the thing most visible in a video.
3. **The visual work in B, C and E** — UI-UX is a scored category and it
   is what reads on camera.
4. **F1–F9** — real work, large, and only partly visible in a demo.
5. **F10–F13** — blocked regardless.
