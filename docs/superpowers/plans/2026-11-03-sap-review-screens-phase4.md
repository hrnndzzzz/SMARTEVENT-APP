# SAP App: Review Screens (Phase 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each reviewer can take exactly its step from the app: the SDS Office approves and signs, returns, or rejects from one review screen, and the Moderator and Dean approve or return a proposal from the event screen. The proposal hub and the demo read right for every role.

**Architecture:** The SDS review screen (`SdsSignScreen`) gains Return and Reject beside Approve and sign. Its overall remark becomes the required reason, and the hub's separate "Return for revision" button goes away. The event screen asks the server whether an event has a SAP proposal (`GET …/sap-proposal`, 404 = no proposal). For a proposal, the second decision button reads "Return for revision", needs remarks, and sends `expected_version`. Then, small carried fixes: the hub's banners per role, the demo's missing steps, and disabled choice chips that still look live.

**Tech Stack:** Flutter (Dart), the Brut design system (`lib/theme/brut.dart`), flutter_test with `MockClient`.

**Spec:** `docs/superpowers/specs/2026-10-30-sds-review-decisions-design.md`, Phase 4 (this branch). Backend: branch `SDS-Workflow-setup` (`git show origin/SDS-Workflow-setup:smartevent-backend/docs/sap-fo-020-frontend-contract.md`). Phase 3's carried items come from its whole-branch review.

## Global Constraints

- App only: `lib/` and `test/` on `Frontend/SDS-Addition-Setup` (pushed at 23853cd). The controller pushes; never push or merge to `develop`.
- Don't stray from the app's design: reuse `BrutScreen`, `BrutHeader`, `BrutFooter`, `BrutButton`, `BrutCard`, `BrutBadge`, `BrutInlineMessage`, `BrutTextField`, `BrutSectionTitle`, `SapSdsOnlyNotice` and the tones (sun = waiting, mint = done, coral = returned/rejected, neutral = info). No new colours, fonts or layouts. Irreversible actions confirm with an `AlertDialog` as `SdsSignScreen._sign` does.
- Wording: say "Moderator" (the organization's adviser), "Dean" (the department's admin) and "SDS Office" in proposal screens.
- Backend facts:
  - SDS `POST …/sap-proposal/return` and `POST …/sap-proposal/sds-reject` take `{expected_version, remarks, section_remarks?}`:
    - `remarks`: 1–3000 characters, not blank.
    - `section_remarks`: an object keyed by `activity_details`, `budget`, `support_requests`, `additional_information`, `clearance` or `other`, each at most 1000 characters. Omitted or `null` keeps the saved ones; an object replaces them.
    - Both are accepted only while `pending_sap_review` (409 otherwise). Return makes it `revision_requested` with `returned_by: sds`. Reject makes it `rejected`, final, and the event becomes `rejected`. Both write the remarks to `sds_review.overall_remarks`.
  - `PUT …/sds-review` saves `overall_remarks` (≤3000) and `section_remarks`. `POST …/sds-sign` needs Part 4 saved.
  - `POST /events/{id}/approve` and `/reject` take `{remarks?, expected_version?}`:
    - `remarks` is at most 2000 characters.
    - `expected_version` (≥1) applies to SAP proposals only: it is the proposal version last read, and a changed proposal answers 409. Other events ignore it.
    - For an event with a SAP proposal, `/reject` is a return for revision: remarks are required (422 "Say what needs to change" when blank). The proposal becomes `revision_requested` with `returned_by` `moderator` or `dean`, the event becomes `draft`, and the history records the decision `returned`.
    - The Moderator acts at `pending_adviser` and the Dean (admin or super admin) at `pending_admin`. Nobody decides their own proposal.
  - `GET /events/{id}/sap-proposal` answers 404 for an event with no proposal (`SapUnavailable` in the app). Organization and department readers may read it.
- Commits: conventional subject, prose body saying what a user saw and why. No `Co-Authored-By` or "Generated with" lines. Stage by path; never commit `linux/`, `macos/`, `windows/` (run `git checkout -- linux macos windows` after flutter commands) or `docs/superpowers/plans/`.
- Tests (PowerShell, from the worktree root): `& "C:\Users\hrnnd\flutter-smartevent\bin\flutter.bat" test --no-pub <files>`. Analyzer: `& "C:\Users\hrnnd\flutter-smartevent\bin\flutter.bat" analyze <files>` (no new issues in touched files).
- Test hosting:
  - A service-backed hub: `ChangeNotifierProvider(create: (_) => AppSettings())` around `MaterialApp(theme: AppTheme.light(), home: …)`, then `tester.pump(const Duration(milliseconds: 300))`.
  - A role: `ChangeNotifierProvider.value(value: AppState()..enterDemo(role: …))` (see `test/signing_test.dart` `hostAsSds`, `test/adviser_decides_test.dart`).
  - A live `SapForm` over `MockClient`: see `test/final_scan_gate_test.dart` `loaded(...)`.

## Review Focus

1. A Return or Reject with a blank overall remark never reaches the server. The buttons stay disabled, and `SapForm` refuses without a request. Pinned in Task 1.
2. A decision on a proposal that changed meanwhile (someone else acted first) says so in words and leaves the screen usable. For SDS this is `SapVersionConflict`; for the Moderator and Dean it is a 409 on `/events/{id}/approve|reject`. Pinned in Tasks 1 and 2.
3. An event with no SAP proposal keeps "Reject" with an optional note, and sends no `expected_version`. Pinned in Task 2.
4. Signing still needs saved Part 4, and Return and Reject do not: the office may send a proposal back before filling Part 4. Pinned in Task 1.
5. The Moderator is never offered the Dean's decision or the reverse, and nobody decides their own proposal, with the new label too. Pinned in Task 2.

---

### Task 1: The SDS Office decides from one screen

**Files:** `lib/api/sap_service.dart` (`returnForRevision` :237-248), `lib/state/sap_form.dart` (`returnForRevision` :752-756, beside `sdsSign` :684), `lib/screens/sap/sds_sign_screen.dart`, `lib/screens/sap/sap_form_screen.dart` (SDS block :292-317, `_return` :63-82, `_ReturnSheet` :402-465), `lib/screens/sap/sds_summary_screen.dart` (:56), tests: new `test/sds_decisions_test.dart`, plus `test/signing_test.dart`, `test/sds_summary_test.dart`, `test/sds_reaches_proposals_test.dart`, `test/demo_reaches_sds_test.dart`, `test/part4_for_the_organization_test.dart` (labels).

**Interfaces — produces:**
- `SapService.returnForRevision(String eventId, {required int expectedVersion, required String remarks, Map<SapRemarkSection, String>? sectionRemarks})`. It sends `section_remarks: _sections(sectionRemarks)` only when non-null.
- `SapService.sdsReject(String eventId, {required int expectedVersion, required String remarks, Map<SapRemarkSection, String>? sectionRemarks})` posts to `…/sds-reject`.
- `SapForm.sdsReturn()` and `SapForm.sdsReject()`, both `Future<String?>`: null on success, otherwise the reason, as `sdsSign` does. Both send `overallRemarks` as `remarks` and `sectionRemarks`, and adopt the returned proposal.
  - A blank `overallRemarks` returns `'Write the overall remark first: it is the reason the organization reads.'` without a request.
  - With no service, both return `sdsSign`'s message.
- `SapForm.returnForRevision(String)`, the hub's `_return` and `_ReturnSheet` are deleted.
- Labels: the hub's and the summary's entry button and the screen header read **"Review and decide"**. The footer button reads **"Approve and sign"**.

- [ ] **Step 1: Failing tests** in `test/sds_decisions_test.dart` (SDS staff, a `loaded('pending_sap_review')`-style form over `MockClient`, saved clearance):
  - `'returning needs the overall remark'`: "Return for revision" and "Reject" have `onPressed == null` while Overall is blank. After `enterText` on Overall they are enabled. A hint containing `'needs an overall remark'` shows only while blank.
  - `'returning sends the remarks and the section remarks'`: type Overall `'Move it to the afternoon.'` and Budget `'Split the venue cost.'`, then tap "Return for revision" and "Return" in the dialog `'Return for revision?'`. The `POST …/return` body equals `{'expected_version': 3, 'remarks': 'Move it to the afternoon.', 'section_remarks': {'budget': 'Split the venue cost.'}}`. The snackbar reads `'Returned for revision.'` and the screen pops.
  - `'rejecting is final and says so'`: the dialog `'Reject this proposal?'` contains `'final'`. Confirming posts to `…/sds-reject` with the same body shape, and the snackbar reads `'Rejected. The organization has been told.'`
  - `'cancelling sends nothing'`: Cancel in either dialog makes no request.
  - `'a changed proposal says so'`: `/return` answers 409. The snackbar shows the conflict message, and the screen stays with its buttons enabled.
  - `'returning does not wait for Part 4'`: with no clearance, Return and Reject are enabled once Overall is filled, and "Approve and sign" stays disabled.
  - Unit tests for `SapForm`: blank Overall gives the refusal with no request. No service gives `sdsSign`'s message.
  - Hub: as SDS at `pending_sap_review`, `find.text('Review and decide')` finds one and `find.text('Return for revision')` finds none.
- [ ] **Step 2: Run, see them fail** — `flutter test --no-pub test/sds_decisions_test.dart`.
- [ ] **Step 3: Implement.**
  - Service and form as in Interfaces.
  - Screen: Remarks section unchanged, plus `maxLength: 3000` on Overall and `1000` on each section, with Overall's `onChanged` rebuilding. A new `BrutSectionTitle('Return or reject')` holds, while Overall is blank, the hint (neutral, `Icons.info_outline`): `'Returning or rejecting needs an overall remark. It is what the organization reads, and it prints on the form.'` Under it go `BrutButton('Return for revision', tone: coral, icon: Icons.undo)` and `BrutButton('Reject', tone: coral, icon: Icons.block)`, both enabled when `_open && overall not blank && !saving`. Then the existing Signature section.
  - The Return dialog body keeps `_ReturnSheet`'s warning: `'It goes back to the organization to change and send again, through the Moderator and Dean. The signatures already collected stay with this revision.'`
  - The Reject dialog body: `'This is final. The organization is told it was rejected and cannot send this proposal again; they would start a new one. Your remarks print on the form.'`
  - Hub and summary entry labels change.
- [ ] **Step 4: Update the label tests** in the files listed ("Review and sign" → "Review and decide", "Sign the proposal" → "Approve and sign"). `part4_for_the_organization_test.dart:405-436` now pins that the hub offers "Review and decide" to SDS and nothing to others. Run `flutter test --no-pub test/sds_decisions_test.dart test/signing_test.dart test/sds_summary_test.dart test/sds_reaches_proposals_test.dart test/demo_reaches_sds_test.dart test/part4_for_the_organization_test.dart` — all pass.
- [ ] **Step 5: Commit** `feat(sap): let the SDS Office approve, return or reject from the review screen`

---

### Task 2: The Moderator and Dean approve or return a proposal

**Files:** `lib/api/event_service.dart` (`approve`/`reject` :174-188), `lib/state/app_state.dart` (`adviserDecision`/`adminDecision` :2512-2557, beside the withdraw at :2386), `lib/screens/event_detail_screen.dart` (`_decide` :23-104, decision row :144-178, `_ApprovalRow` :578-600), `lib/screens/home_screen.dart` (`AlertWidget` :363-371), tests: new `test/department_decides_proposal_test.dart`, plus `test/adviser_decides_test.dart` and `test/event_detail_test.dart` as needed.

**Interfaces — produces:**
- `EventService.approve(String eventId, {String? remarks, int? expectedVersion})` and `reject(...)`. The body adds `'expected_version'` only when non-null.
- `AppState.proposalVersionFor(EventItem event)` returns `Future<int?>`: the proposal's `version` from `sapService.fetch`, or null on `SapUnavailable`. Other errors propagate.
- `AppState.adviserDecision` and `adminDecision` gain `int? expectedVersion`. When it is non-null and `approved` is false (a proposal return), `event.rejectedBy` is not set, and the event's status comes from the server's response as for any decision.

- [ ] **Step 1: Failing tests** in `test/department_decides_proposal_test.dart`:
  - `'a proposal offers Return for revision'`: an adviser views a `pendingAdviser` event whose `GET …/sap-proposal` answers a proposal at version 4. The row shows "Return for revision" and "Approve", with no "Reject". The same holds for an admin at `pendingAdmin`.
  - `'a plain event keeps Reject'`: the proposal GET answers 404. The row shows "Reject" and "Approve". Rejecting with a blank note posts `{}` (no `expected_version`).
  - `'returning needs remarks and sends the version'`: in the dialog `'Return for revision?'`, "Return" is disabled until "What needs changing" has text. Confirming posts `/events/{id}/reject` with `{'remarks': 'Fix the budget.', 'expected_version': 4}`. The snackbar contains `'Returned for revision'`.
  - `'approving a proposal sends the version'`: the `/approve` body includes `'expected_version': 4`.
  - `'a changed proposal says so'`: a 409 with detail `'This proposal has changed since you opened it'` shows that text, and the buttons stay usable.
  - `'nobody decides their own'`: the existing own-proposal rule still hides the row (one case with a proposal).
  - `'the history names a return'`: an `ApprovalRecord` with decision `'returned'` reads `'Returned for revision'` in coral.
  - `'each reviewer counts only their own step'`:
    - The home alert counts only `pendingAdviser` events for an adviser, only `pendingAdmin` for an administrator, and only `pendingInstitutional` for SDS staff.
    - Any other reviewing role keeps today's `isPending` count.
    - Use two adviser-stage events and one admin-stage event; the adviser reads `'2 events awaiting a decision'`.
- [ ] **Step 2: Run, see them fail.**
- [ ] **Step 3: Implement.**
  - The decision row becomes a small `StatefulWidget` that loads `proposalVersionFor(event)` once. In demo mode it treats the event as a proposal with no version.
  - While loading, both buttons are disabled. On error, a coral `BrutInlineMessage` shows the error, with a neutral "Try again" `BrutButton`.
  - `_decide` takes `isProposal` and `expectedVersion`. For a return, the field is required, labelled `'What needs changing'`, with `maxLength: 2000`, and the confirm button reads "Return". Approve keeps `'Feedback (optional)'`.
  - `_ApprovalRow` maps `'returned'` to coral `'Returned for revision'`.
  - `AlertWidget` counts by the role's own stage, as tested.
- [ ] **Step 4: Run** `flutter test --no-pub test/department_decides_proposal_test.dart test/adviser_decides_test.dart test/adviser_reaches_reviews_test.dart test/event_detail_test.dart test/home_screen_test.dart` (whichever of the last exist) — all pass.
- [ ] **Step 5: Commit** `feat(events): let the Moderator and Dean return a proposal with remarks`

---

### Task 3: The proposal hub reads right for whoever opens it

**Files:** `lib/screens/sap/sap_form_screen.dart` (banners :148-189), `lib/screens/sap/sap_proposal_flow.dart` (status card switch :270-315, lock note :318-328), `lib/state/sap_form.dart` (`statusOf` Part 5 :803-812), tests: `test/proposal_whereabouts_test.dart` (add a group).

**What changes (each pinned by one test in a new group `'the hub, read by each role'`):**
- The department-review banner reads `'With the Moderator and Dean. They approve it before it goes to the SDS Office.'` for everyone, dropping "your".
- The rejected banner: SDS staff read `'Rejected by the SDS Office. This proposal is final.'` plus the remarks, without the "start a new one" advice. Everyone else is unchanged.
- The awaiting-evaluation banner: SDS staff read `'The activity has run. Record how it went in Part 6.'` (sun, `Icons.hourglass_top`). Everyone else is unchanged.
- The status card at a null state (failed load) shows neutral `'Not loaded'` with `form.error` or `'The proposal could not be loaded. Open it again to retry.'`, not "Sent / Waiting on the SDS Office."
- The lock note at `sdsSigned`, `approved` and `completed` reads `'Parts 1 to 3 are locked: the SDS Office has signed this revision.'` `pendingReview` keeps its text.
- The hub's Part 5 row is `locked` for `revisionRequested` when `returnedBy` is `moderator` or `dean`. An SDS return keeps `partial`.

- [ ] Steps: failing tests, then fail, implement, pass with `flutter test --no-pub test/proposal_whereabouts_test.dart test/sap_proposal_test.dart test/returned_proposal_test.dart`, then commit `fix(sap): word the proposal hub for whoever is reading it`.

---

### Task 4: The demo shows each role's step

**Files:** `lib/state/sap_form.dart` (`seedLocally` :852), `lib/state/demo_data.dart` (events :133-217, `DemoProposals`), `lib/screens/event_detail_screen.dart` (demo seeding :262-270), `lib/screens/sds_proposals_screen.dart` (list :44-48, demo seeding :97-105), tests: `test/demo_mode_test.dart`, `test/sds_reaches_proposals_test.dart`, `test/demo_proposal_consistency_test.dart`.

**Interfaces:**
- Consumes: Task 1's labels and Task 2's decision row (in demo mode, treated as a proposal).
- Produces:
  - `SapForm.seedLocally(..., SapClearance? clearance)` sets the seeded proposal's clearance and the form's.
  - `DemoProposals.clearanceFor(EventItem)` returns a filled `SapClearance` for `demo-ev-2`, `demo-ev-5` and `demo-ev-6`, otherwise null.

**What changes:**
- Both demo seeding sites pass `clearance: DemoProposals.clearanceFor(event)`. The demo's SDS role can then draw a signature on demo-ev-6, and "Approve and sign" enables. Its confirmation answers the existing "not saved to the server yet" message. Part 4 shows answers for the approved and completed demo proposals.
- Append `demo-ev-7` last, at `pendingAdmin`, proposed by `'demo-account-officer'`, with its own `_byEvent` details, budget and support. Its budget lines add up to its budget, as demo-ev-6's do. This gives the demo's Dean a decision.
- In demo mode the SDS list leaves out `pendingAdviser` and `pendingAdmin` events. The live list stays as the server scopes it.

- [ ] Steps:
  - Failing tests:
    - demo SDS staff on demo-ev-6 see no "Confirm Part 4" message, and the pad is enabled;
    - the demo admin's event detail for demo-ev-7 shows "Return for revision" and "Approve";
    - the demo SDS list has neither demo-ev-1 nor demo-ev-7;
    - demo-ev-7's budget lines sum to its budget.
  - Then fail, implement, and pass with `flutter test --no-pub test/demo_mode_test.dart test/sds_reaches_proposals_test.dart test/demo_proposal_consistency_test.dart test/events_hub_draft_test.dart test/one_proposal_at_a_time_test.dart test/adviser_reaches_reviews_test.dart`, fixing count ripples in the tests the way Phase 3 did (`pumpHub`).
  - Commit `fix(demo): give every reviewing role a proposal to act on`.

---

### Task 5: Disabled choices look and read disabled

**Files:** `lib/theme/brut.dart` (`BrutChip` :1947-1984), `lib/screens/sap/sap_form_fields.dart` (`SapSingleChoice` :47-56, `SapMultiChoice` :95-102), test: new `test/disabled_choice_test.dart`.

**What changes:** `BrutChip.onTap` becomes `VoidCallback?`, and `BrutChip` passes `enabled: onTap != null` to `BrutSurface` (it already has `enabled`). The two SAP choice widgets pass `null` when disabled instead of `() {}`. Other `BrutChip` callers keep passing callbacks.

- [ ] Steps:
  - Failing tests: a disabled `SapSingleChoice` has every chip's `BrutSurface.enabled == false`, and its semantics report not enabled; an enabled one is unchanged and still selects on tap.
  - Then fail, implement, and pass with `flutter test --no-pub test/disabled_choice_test.dart test/part4_for_the_organization_test.dart test/sap_screens_test.dart`.
  - Commit `fix(sap): show a choice that cannot be changed as disabled`.

---

### Task 6: Full suite (controller)

- [ ] `flutter test --no-pub` passes, and `flutter analyze lib test` shows no errors. Then `git checkout -- linux macos windows`, and the controller pushes `Frontend/SDS-Addition-Setup` by name.
