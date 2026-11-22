# First sign-in tour

## Why
New users miss the dashboard's hidden gestures: swiping between Menu,
Dashboard and Events, holding a tile to peek, tapping the date for the
Planner, and the eye that covers the budget. The request was a guide on
first open, like the one GCash shows.

## What
A spotlight tour after the first sign-in. The screen dims, one real control
is lit at a time, and a card shows the screen and "n of N", a title, a line,
Skip and Next (Done on the very last step).

It is **one chained walk-through** (chosen over a separate tip on each
screen's first visit): the dashboard, the Menu, then Money, Inventory,
Analytics and Flagged opened in turn, then the Events page, All events and
the cover of a new proposal, ending back on the dashboard. Skip or Back
anywhere ends the whole tour. It is about 28 stops for a Treasurer.

- **Who sees it:** real accounts and the demo. It shows once per account
  on each phone (`tour.seenBy` in shared preferences, `demo` for the
  demo). Settings → More → Replay the tour runs the whole chain again.
- **Roles:** only the three-screen shell (Officer, Treasurer, Adviser,
  Admin, Super Admin). SDS staff and signatories land on one-job screens
  and get no tour.
- **Stops by role:** a stop whose control is not on screen is left out,
  so the Adviser, who reviews money rather than recording it, gets no
  Record stops. Create event is shown only to whoever may propose.

## How it is put together
- Controls are marked with `TourSpot('money.figures', child: …)`, a name
  rather than a GlobalKey, so a screen opened twice cannot crash on a
  duplicate key; the first spot of a name answers (the top card of a
  list).
- `showSpotlightTour` lights one screen's steps. It waits until a spot has
  mounted and the screen has finished opening, and returns false only
  when the person chose to stop.
- `lib/screens/app_tour.dart` holds the legs: which page to swipe to or
  which screen to open, and the steps for it. Create event opens a new
  form's cover, which saves nothing until Part 1 is finished.
- A spot that leaves no room above or below it (the Menu's grid) gets
  the card over its lower edge.

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
