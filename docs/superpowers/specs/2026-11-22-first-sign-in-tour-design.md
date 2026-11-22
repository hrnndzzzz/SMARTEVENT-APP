# First sign-in tour

## Why
New users miss the dashboard's hidden gestures: swiping between Menu,
Dashboard and Events, holding a tile to peek, tapping the date for the
Planner, and the eye that covers the budget. The request was a guide on
first open, like the one GCash shows.

## What
A spotlight tour after the first sign-in. The screen dims, one real control
is lit at a time, and a card shows "n of N", a title, a line, Skip and
Next (Done on the last step).

- **Who sees it:** real accounts and the demo. It shows once per account
  on each phone (`tour.seenBy` in shared preferences, `demo` for the
  demo). Settings → More → Replay the tour shows it again.
- **Roles:** only the three-screen shell (Officer, Treasurer, Adviser,
  Admin, Super Admin). SDS staff and signatories land on one-job screens
  and get no tour.
- **Steps:** top bar, date, budget tile, Record button, page bar. A step
  whose control is not on screen is left out, so the Adviser, who reviews
  money rather than recording it, gets four.

## Approaches
- **Hand-built spotlight (chosen).** About 150 lines in
  `lib/widgets/spotlight_tour.dart`: a see-through route, a dark layer with
  a cut-out, and a Brut card. It matches the design system, honours Reduce
  motion, and adds no dependency.
- **`showcaseview` / `tutorial_coach_mark`.** Rejected: a new dependency
  with its own tooltip look to restyle, and APIs that change between major
  versions.
- **Intro slides before sign-in.** Rejected: they can't point at real
  controls or vary by role.

## Behaviour worth knowing
- The tour waits until nothing is on top of the dashboard (sign-in screen,
  biometric offer, update prompt) and until any closing route has finished
  its transition, so the cut-out lines up with its target.
- It is marked seen when it starts, so closing the app mid-tour doesn't
  force it on the person again.
- If storage fails, the tour counts as seen, so a broken store never
  replays it on every launch.
