# SAP App: What the Organization Sees (Phase 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Flutter app understands the new proposal flow — department review, who returned a proposal, a final rejection, the SDS Office's remarks — and shows the organization where its proposal is and why, while keeping SDS-only actions to SDS staff.

**Architecture:** The model learns one new state (`pendingDepartmentReview`) and `returnedBy`; the proposal screens (the six-part hub, the wizard's status card, Part 4) read them to show who has the proposal and the remarks. The current role comes from `AppState.currentRole`, read with the same "no provider in tests" fallback `SapProposalFlow` already uses. Only SAP-specific screens change their stage wording; event-status labels shared with the generic signatory flow stay as they are.

**Tech Stack:** Flutter (Dart), the app's Brut design system (`lib/theme/brut.dart`), flutter_test with `MockClient`.

**Spec:** `docs/superpowers/specs/2026-10-30-sds-review-decisions-design.md`, Phase 3 (in this checkout). Backend contract: `smartevent-backend/docs/sap-fo-020-frontend-contract.md` on branch `SDS-Workflow-setup` (`git show origin/SDS-Workflow-setup:smartevent-backend/docs/sap-fo-020-frontend-contract.md`).

## Global Constraints

- App only: changes under `lib/` and `test/`. Branch `Frontend/SDS-Addition-Setup` (this worktree has it checked out; develop is already merged in at 6932184). The controller pushes; never push or merge to `develop`.
- Don't stray from the app's design: reuse `BrutInlineMessage`, `BrutCard`, `BrutBadge`, `BrutButton`, `BrutFooter`, `MonoLabel` and the tones as the SAP screens already use them (sun = waiting, mint = done, coral = returned/rejected, neutral = info). No new colours, fonts or layouts.
- Backend facts (from `SDS-Workflow-setup`): proposal states `draft`, `pending_department_review`, `pending_sap_review`, `revision_requested`, `sds_signed`, `approved`, `completed`, `rejected`. Event status while with the department: `pending_adviser` (Moderator) or `pending_admin` (Dean); with the SDS Office: `pending_institutional_review`; returned: `draft`; rejected: `rejected`. Proposal JSON adds `returned_by` (`moderator` | `dean` | `sds` | null). A return's reason is `return_remarks`; the SDS Office's remarks (also a rejection's reason) are `sds_review.overall_remarks` and `sds_review.section_remarks`. Part 4 is editable by SDS staff only while `pending_sap_review`. The final scan is accepted only while `sds_signed`.
- Wording: the Moderator is the organization's adviser; the Dean is the department's admin; say "Moderator", "Dean" and "SDS Office" in proposal screens.
- Commits: conventional subject and a prose body saying what a user saw and why. No `Co-Authored-By` or "Generated with" lines. Stage files by path; never commit `linux/`, `macos/`, `windows/` changes (flutter rewrites their line endings — run `git checkout -- linux macos windows` after flutter commands) or `docs/superpowers/plans/`.
- Tests (PowerShell, from the worktree root): `& "C:\Users\hrnnd\flutter-smartevent\bin\flutter.bat" test --no-pub <files>`; analyzer: `& "C:\Users\hrnnd\flutter-smartevent\bin\flutter.bat" analyze <files>` (no new issues in touched files).
- Test hosting: a service-backed hub needs `ChangeNotifierProvider(create: (_) => AppSettings())` around `MaterialApp(theme: AppTheme.light(), home: …)` and `tester.pump(const Duration(milliseconds: 300))` (the spinner never settles); a screen that reads the role needs `ChangeNotifierProvider.value(value: AppState()..enterDemo(role: UserRole.sdsStaff))` (see `test/sds_reaches_proposals_test.dart`, `test/adviser_decides_test.dart`). Existing proposal JSON fixtures: `test/returned_proposal_test.dart:31-55`, `test/revision_and_evaluation_test.dart:31-68`.

## Review Focus

1. A proposal at `pending_department_review` must never show as "no state" or "With the SDS Office" anywhere the organization looks. Pinned in Tasks 1 and 2.
2. A proposal the Moderator or Dean returned must not say the SDS Office sent it back. Pinned in Task 2.
3. A rejected proposal must read as final — no "submit", no "needs changes" wording. Pinned in Tasks 2 and 4.
4. A non-SDS account must not be offered Part 4 editing or the hub's SDS actions; SDS staff keep them in `pending_sap_review`. Pinned in Task 3.
5. The final-scan upload must be reachable once the SDS Office has signed and all nine slots are recorded. Pinned in Task 5.

---

### Task 1: The model knows department review and who returned it

**Files:** `lib/api/models/sap_proposal.dart` (enum `SapState` :21-52, `SapProposal` :871-992), `lib/state/sap_form.dart` (`_adopt` :251-265, `seedLocally` :818-841), `test/sap_state_test.dart`, `test/sap_proposal_test.dart`.

**Interfaces — produces:**
- `SapState.pendingDepartmentReview('pending_department_review', 'With the department')`, placed after `draft`. `pendingReview` keeps meaning "with the SDS Office". `rejected`'s doc comment says it is the SDS Office's final decision (POST `/sds-reject`), not "reserved".
- `enum SapReturnedBy { moderator('moderator', 'the Moderator'), dean('dean', 'the Dean'), sds('sds', 'the SDS Office') }` with `wireName`, `label` (as written, for "Returned by …"), and `static SapReturnedBy? fromWire(String?)`.
- `SapProposal.returnedBy: SapReturnedBy?` parsed from `returned_by`.
- `SapForm.returnedBy` (from the proposal); `seedLocally` gains optional `returnedBy` and `revisionNo` (default 0) so tests can seed a returned or resubmitted proposal.

- [ ] **Step 1 — failing tests:** `pending_department_review` parses to `SapState.pendingDepartmentReview`; `returned_by: 'dean'` parses to `SapReturnedBy.dean`, a missing or unknown value to `null`; a form loaded from such JSON exposes `returnedBy`; `seedLocally(state: SapState.revisionRequested, returnedBy: SapReturnedBy.moderator)` exposes it too. Update `test/sap_state_test.dart`'s stored-state list for the new value.
- [ ] **Step 2:** run them, see them fail. **Step 3:** implement. **Step 4:** `flutter test --no-pub test/sap_state_test.dart test/sap_proposal_test.dart test/printout_test.dart test/returned_proposal_test.dart` passes (printout_test loops `SapState.values`).
- [ ] **Step 5 — commit:** `feat(sap): know department review and who returned a proposal`

---

### Task 2: The organization sees where its proposal is, and why

**Files:** `lib/screens/sap/sap_form_screen.dart` (returned banner :148-157, submit snackbar :305, print info :246-265), `lib/screens/sap/sap_proposal_flow.dart` (`onSubmit` snackbar :120, `SapProposalStatus` :247-318), `lib/screens/sap/sap_part3_screen.dart` (footer label :288), `lib/screens/sap/proposal_steps.dart` (leave dialog :54-57), tests `test/returned_proposal_test.dart`, `test/revision_and_evaluation_test.dart`, new `test/proposal_whereabouts_test.dart`.

**Interfaces — consumes:** `SapState.pendingDepartmentReview`, `SapForm.returnedBy`, `SapReturnedBy.label` (Task 1); existing `SapForm.returnRemarks`, `SapForm.overallRemarks`/`sectionRemarks`.

**What changes:**
- After sending: "Sent for department review." (snackbar :120 and the hub's :305); Part 3's wizard footer button reads "Send for review"; the leave dialog says nothing has been sent yet (no SDS mention).
- Hub banners (one at a time, in `BrutInlineMessage`, matching the existing returned banner's style):
  - `pendingDepartmentReview` — sun, `Icons.hourglass_top`: "With your Moderator and Dean. They approve it before it goes to the SDS Office."
  - `revisionRequested` — coral (existing banner): "Returned by {returnedBy.label}: {returnRemarks}" — falling back to the current wording only when `returnedBy` is null; when returned by the SDS Office and section remarks exist, list them under it ("Budget: …").
  - `rejected` — coral, `Icons.block`: "Rejected by the SDS Office. This proposal is final; start a new one to try again." followed by the SDS overall remark and section remarks.
- Print info text: a rejected proposal prints with the SDS Office's rejection mark (no "unsigned copy" wording).
- `SapProposalStatus` (the wizard's "Where it is" card) gains cases: `pendingDepartmentReview` "With the Moderator and Dean" (sun); `revisionRequested` "Returned" with "by {label}" and the remark (coral); `rejected` "Rejected" (coral, final). Its fallback `_ => ('Sent', 'Waiting on the SDS Office.')` must no longer be reached by `pendingDepartmentReview`.

- [ ] **Step 1 — failing tests** (service-backed hub via `MockClient`, as in `returned_proposal_test.dart`): a `pending_department_review` proposal shows the department banner and no "SDS Office sent"; a `revision_requested` proposal with `returned_by: 'dean'` and `return_remarks: 'Move it to the afternoon'` shows "Returned by the Dean" and the remark; with `returned_by: 'sds'` and `sds_review.section_remarks: {'budget': 'Meals over the allowance'}` it also shows "Meals over the allowance"; a `rejected` proposal with `sds_review.overall_remarks: 'Not an organizational activity'` shows "Rejected by the SDS Office", the remark, and an enabled-nowhere "Submit for review" (`onPressed == null`). Update `returned_proposal_test.dart:89`'s pinned SDS wording to the `returned_by` behaviour.
- [ ] **Step 2–4:** fail, implement, pass: `flutter test --no-pub test/proposal_whereabouts_test.dart test/returned_proposal_test.dart test/revision_and_evaluation_test.dart test/sap_screens_test.dart test/printout_test.dart test/demo_reaches_sds_test.dart`.
- [ ] **Step 5 — commit:** `feat(sap): show the organization where its proposal is and who returned it`

---

### Task 3: Part 4 and the SDS actions belong to the SDS Office

**Files:** `lib/screens/sap/sap_part4_screen.dart` (button :167, every `enabled:` :177-304), `lib/screens/sap/sap_form_screen.dart` (SDS block :266-288), a role helper next to `_appOf` in `lib/screens/sap/sap_proposal_flow.dart:190-196` (reuse it; don't duplicate the fallback), tests `test/sap_screens_test.dart` (Part 4 tests :464-510), `test/signing_test.dart:166-185`, new `test/part4_for_the_organization_test.dart`.

**Interfaces — produces:** a single place that answers "is the current account SDS staff" from `AppState.currentRole == UserRole.sdsStaff`, returning `false` when no `AppState` is provided. Part 4 is editable only when that is true, `form.state == SapState.pendingReview`, and `!form.isReadOnly`.

**What changes:**
- Part 4 for anyone else (and for SDS outside `pending_sap_review`): every field disabled, no "Confirm clearance" action (`onPressed: null`), and above the answers an outcome card in the existing style: "With the Moderator and Dean" / "With the SDS Office" (sun), "Needs revision" (coral, when returned by the SDS Office), "Approved" (mint, `sdsSigned`/`approved`/`completed`), "Rejected" (coral). Under it the SDS Office's remarks: the overall remark and each section remark with its section label (`SapRemarkSection.label`). Before any SDS remark exists, say so plainly ("No remarks from the SDS Office yet.").
- The hub's SDS block (Review and sign, Return for revision) shows only for SDS staff.

- [ ] **Step 1 — failing tests:** with an organization account (`enterDemo(role: UserRole.treasurer)`) a `pending_sap_review` Part 4 shows disabled fields, no enabled confirm, and the "With the SDS Office" card; a `sds_signed` one shows "Approved" plus seeded SDS remarks; with SDS staff at `pending_sap_review` the fields are enabled; SDS staff on a hub see "Review and sign", a treasurer does not. Update the existing Part 4 tests to host SDS staff where they edit.
- [ ] **Step 2–4:** fail, implement, pass: `flutter test --no-pub test/part4_for_the_organization_test.dart test/sap_screens_test.dart test/signing_test.dart test/field_limits_test.dart test/sds_summary_test.dart`.
- [ ] **Step 5 — commit:** `fix(sap): keep Part 4 and the SDS actions to the SDS Office`

---

### Task 4: Proposal screens outside the form follow the new flow

**Files:** `lib/screens/sds_proposals_screen.dart` (`stageOf` :23-38, `_sapStateFor` :143-151), `lib/screens/event_detail_screen.dart` (`_demoSapState` :845-853, rejected "Edit proposal" :303-322), `lib/screens/events_hub_screen.dart` (`_CreateBand._state` :129-152), `lib/screens/events_screen.dart` (`_StatusFilter` :375-396), `lib/widgets/event_progress_bar.dart` (`EventStage.of` :18-72), tests named in the steps.

**Ruling that binds this task:** event-status labels shared with the generic signatory flow (`AppState` `statusLabel`/`tone`, `lib/widgets/event_status.dart`, the calendar) stay as they are — `pending_institutional_review` also means "with the signatories" there. Change only what is SAP-specific or now wrong in both flows.

**What changes:**
- SDS proposals list: `pendingAdmin` → "With the Dean"; `pendingInstitutional` → "With the SDS Office"; `rejected` → "Rejected" (not "Returned").
- Demo/list state mapping (`_sapStateFor`, `_demoSapState`): `pendingAdviser`/`pendingAdmin` → `pendingDepartmentReview`; `pendingInstitutional` → `pendingReview`; `rejected` → `rejected`.
- Rejected event (final under SAP): the events hub band says "Rejected" (not "Came back — needs changes"); the event detail's button reads "Open proposal" (not "Edit proposal") for a rejected event; the events filter's "Returned" chip, which only ever matched `rejected`, reads "Rejected".
- `EventStage.of`: `pendingAdmin` is the Dean's step, not "with the SDS Office" — map it to the review stage before the SDS Office (add a stage only if no existing one fits), and `pendingInstitutional` to the SDS stage.

- [ ] **Step 1 — failing tests:** update `test/event_stage_test.dart:18-21`, `test/sds_reaches_proposals_test.dart:61-71`, `test/event_detail_test.dart` (rejected button text) and add assertions for the band and filter labels.
- [ ] **Step 2–4:** fail, implement, pass: `flutter test --no-pub test/event_stage_test.dart test/sds_reaches_proposals_test.dart test/event_detail_test.dart test/events_hub_draft_test.dart test/event_status_test.dart test/one_proposal_at_a_time_test.dart`.
- [ ] **Step 5 — commit:** `fix(sap): name the Dean's step and treat a rejection as final in the event screens`

---

### Task 5: The final scan follows the SDS signature

**Files:** `lib/screens/sap/sap_part5_screen.dart` (upload gate :295-300, hint :263-271, scan wording :281-285), `lib/api/sap_service.dart` (doc :419, :444), new `test/final_scan_gate_test.dart`.

**What changes:** the "Upload the signed scan" button enables when the form is writable, all nine slots are recorded, and `form.state == SapState.sdsSigned` (the server accepts the scan only then). The slot hint says slots 2 and 3 may be recorded in either order and slots 5–9 open after the SDS Office signs. The scan wording says what the server checks: a flattened PDF of the signed form, at least three pages and the same page count as the stored form, at most 10 MB — not "exactly six pages".

- [ ] **Step 1 — failing test:** a Part 5 host with a `MockClient` whose `/workflow` answers nine recorded slots: at `sds_signed` the upload button is enabled; at `pending_sap_review` it is not.
- [ ] **Step 2–4:** fail, implement, pass: `flutter test --no-pub test/final_scan_gate_test.dart test/printout_test.dart`.
- [ ] **Step 5 — commit:** `fix(sap): open the final-scan upload once the SDS Office has signed`

---

### Task 6: Full suite (controller)

- [ ] `flutter test --no-pub` passes and `flutter analyze lib test` shows no new errors; `git checkout -- linux macos windows`; the controller pushes `Frontend/SDS-Addition-Setup` by name.
