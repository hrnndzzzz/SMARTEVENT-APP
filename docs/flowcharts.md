# SMARTEVENT flowcharts

Six Mermaid diagrams: five covering the backend's 147 endpoints across 22
routers, and one covering how the app behaves when there is no live server.
Paste any of them whole into <https://mermaid.live> — the first line of each
file must read `flowchart LR`.

| # | File | Covers |
|---|---|---|
| 1 | [system-flowchart.mmd](system-flowchart.mmd) | Roles, the SAP proposal spine, the nine physical signatures, printing |
| 2 | [flowchart-before-event.mmd](flowchart-before-event.mmd) | Pre-activity compliance: logistics, participants, requirements, personnel, vehicles, readiness |
| 3 | [flowchart-after-event.mmd](flowchart-after-event.mmd) | Closure: completion, attendance, parallel activities, the three closure reports |
| 4 | [flowchart-money-and-assets.mmd](flowchart-money-and-assets.mmd) | Income, expenses, receipt OCR and duplicate detection, approval, the purchase-to-inventory bridge |
| 5 | [flowchart-admin-and-reference.mmd](flowchart-admin-and-reference.mmd) | Registration and OTP, sign-in, roles and scope, reference data, oversight and audit |
| 6 | [flowchart-app-modes.mmd](flowchart-app-modes.mmd) | Flutter-side: demo mode and offline viewing |

## How they fit together

Chart 1 is the spine: a proposal going from draft to approved. Charts 2 and 3
are the bookends around the activity itself — everything that must be verified
before it may go ahead, and everything that must be accounted for afterwards.
Chart 4 is the money, which touches an event at several points but has its own
lifecycle. Chart 5 is everything that has to exist before any of it works.

Three cross-chart connections worth following:

- **Chart 2 gates chart 1.** `require_pre_activity_clearance` is checked at SAP
  submission, at the Dean's approval, and at final approval. A proposal cannot
  advance while its compliance evidence is incomplete.
- **Chart 1 unlocks chart 3.** Post-activity submissions stay locked until the
  event is marked completed.
- **Chart 4 feeds the inventory in chart 4 itself.** An approved expense with
  asset line items becomes stock through `complete-purchase`, which is the only
  path from spending money to owning equipment.

## Chart 6 is the odd one out

Charts 1 to 5 are the backend. Chart 6 is the Flutter app, and answers the two
questions no endpoint can: what happens with no server at all (demo mode), and
what happens when the server was there and goes away (offline viewing).

It also records the pattern that caused most of the demo-mode defects: `_runLoad`
returns early in demo mode, so a feature without its own demo branch shows an
error or nothing, and a branch written *inside* the `_runLoad` callback is
unreachable because `_runLoad` has already returned.
