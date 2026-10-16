# Phase 3: printable attendance and post-activity closeout

> Rollout update: Phase 2 and this migration were applied to the live project on
> 5 October 2026; this phase is recorded as `20261005105058_phase3_execution_and_closure`.
> Statements below about pending deployment and in-memory sessions are historical.
> The current Flutter app uses shared secure-storage sessions and dedicated module
> routes. See `../FRONTEND_INTEGRATION.md` for current verification.

Implemented locally on 4 October 2026 under the approved revised plan. Uses the
existing backend and Flutter app, not a separate workspace website. QR boarding
passes/scanning were replaced with a print-ready participant signature sheet.
The previously added web workspace router/static files were removed. Current
implementation notes retain the backend/API design; the removed uncommitted web
files were not archived as a recoverable Git snapshot.

## User workflow and role requirements

1. Admin records participating students while the proposal is draft/rejected.
   Students have roster entries only, without accounts or an upload portal.
2. Admin/Adviser records equivalent parallel learning activities for students
   unable to attend, including objectives, instructions, reason and optional due
   date. Their participation mode becomes `parallel`; they are excluded from the
   attending roster, pre-activity student requirements and travelling PIC count.
3. Follow the Phase 2 readiness gate and sequential Adviser/Admin/institutional
   approval workflow. Adviser-created proposals skip Adviser self-review.
4. After approval, scoped Admin/Super Admin/Adviser opens **Attendance PDF** in
   the existing Flutter app, previews it and uses native print/share controls.
   The A4 sheet lists student number, participant name and a blank signature
   column. Names sort alphabetically; headers repeat on subsequent pages.
5. Participants sign the paper beside their names. Staff uploads the signed
   scan/photo/PDF under Post-activity, records a reference and verifies it.
   Printing itself does not mark anyone present, complete an event or approve it.
6. Scoped Admin/Super Admin/Adviser marks an approved event completed with the
   actual completion date and notes. The date must be on/after the event date
   and no later than today's Philippine date. Existing approval history remains.
7. Completion creates the required learning-journal checklist for active
   attending students. Staff uploads work or batch-verifies physical originals;
   students do not upload documents themselves. Legacy completed events can
   initialize the checklist without rewriting their approval/completion history.
8. Staff uploads and verifies PIC debriefing/assessment and final-expense reports.
   These are evidence records, not fabricated transactions or automatic changes
   to the existing financial ledger. Alternate work can likewise be uploaded or
   verified physically by staff after approval/completion.
9. Post-activity closeout becomes `CLOSED` when all applicable evidence is
   verified. The activity stays `completed`; closeout is a separately derived
   result. Replacing verified evidence or adding an outstanding requirement
   reopens closeout until fresh verification.

The signed attendance sheet is required when active attending participants exist.
Debriefing/final-expense reports remain required. Active parallel participants
need verified assignments; ordinary post-activity journals do not apply to them.
Corrections/restoration to attending require notes and preserve the audit trail.

Officer stays read-only. Treasurer retains existing pre-activity logistics access
but cannot access student/attendance/closeout files. Signatory reviews assigned
institutional events in order, without student records. SDS Staff has no new
access. An Organization President role was not added.

## Paper trail, security and boundaries

- Structure stays frozen during institutional review/approval. Parallel
  assignment/correction is allowed in draft/rejected or completed, not mid-review.
- Withdrawn participants are excluded from printed attendance. The generated PDF
  reflects the current active attending roster; it is not an immutable historical
  snapshot or a digitally signed attendance record.
- Files reuse private proposal-letter storage but are not proposal-letter rows.
  Scoped, ID-based file endpoints issue five-minute links; response lists never
  expose private object references. Signed attendance and closure files are staff-only.
- Uploads accept PDF/JPEG/PNG up to 10 MB. Versions protect against stale upload
  or review; replacement clears prior verification. Reviews record actor, time,
  evidence mode and remarks. Writers lock the parent event before changes.
- Learning objectives, document authenticity, actual attendance and full CHED
  compliance still require institutional assessment. These screens do not certify
  legal compliance, notarization authenticity or equivalent academic outcomes.
- Existing ReportLab rendering, authentication, authorization, audit, storage
  and review helpers were reused. No new backend production dependency was added.

## Existing Flutter application integration

Source roots:

- Backend: `C:\Users\hrnnd\Documents\thesis\SMARTEVENT-APP\smartevent-backend`.
- Flutter: `C:\Users\hrnnd\Documents\thesis\SMARTEVENT-APP`.

Entry: Dashboard -> **Events & compliance**. The module provides backend staff
login/password setup, scoped event proposals, review order, logistics, student
checklists, attendance preview and post-activity forms. It uses custom backend
JWTs in memory. Closing/reopening the module requires sign-in again. Other
existing dashboard/finance/inventory placeholders were not rewritten.

Configure the API address, for example:

```powershell
flutter run --dart-define=SMARTEVENT_API_URL=https://your-backend.example
```

Debug Android emulator default: `http://10.0.2.2:8000`. Physical devices need a
reachable address; release builds enforce HTTPS. Android INTERNET permission and
debug-only HTTP allowance were added. `file_selector` provides native document
picking; `printing` supplies native preview/print/share. Dependencies are resolved
in the existing `pubspec.lock`. No new hosted app or workspace is required.

Security finding: an existing Flutter Supabase helper contained a hardcoded
privileged service-role key. That value was removed, and the helper now accepts
only compile-time publishable/anon keys. **Rotate the exposed privileged key**
separately; deleting it from source does not invalidate it. New event/compliance
screens use backend APIs, not direct privileged Supabase calls. Older inventory
direct-table integration remains separate work and must not regain privileged keys.

## API additions

All paths below are under `/events/{event_id}` and require scoped staff access.

| Endpoint | Action/stage |
|---|---|
| GET `/attendance.pdf` | Approved/completed; downloads PDF without writes. |
| POST `/complete` | Approved; actual date/notes, completion actor and timestamps. |
| GET `/post-activity` | Closeout blockers, report metadata and parallel assignments. |
| POST `/post-activity/initialize` | Completed; initialize legacy journal requirements. |
| POST `/post-activity/requirements` | Completed; add post-activity requirement. |
| POST `/post-activity/compliance/{record_id}/upload` | Completed; staff upload plus current version. |
| POST `/post-activity/compliance/batch-review` | Completed; physical/digital batch of 1-100 current records. |
| POST `/post-activity/documents` | Signed attendance approved/completed; other reports completed. |
| POST `/post-activity/documents/{id}/review` | Applicable stage; current submitted version and notes. |
| POST `/parallel-activities` | Draft/rejected/completed; assign or replace with current version. |
| PATCH `/participants/{id}/participation` | Draft/rejected/completed; restore attending with reason. |
| POST `/parallel-activities/{id}/upload`, `/{id}/review` | Approved/completed; record and verify alternative work. |
| GET `/parallel-activities/{id}/file` | Authorized private work link. |

Existing `/compliance/{id}/file` and `/compliance-documents/{id}/file` serve
authorized student/report files. `/compliance-workspace` is intentionally absent.

## Database rollout: approval still required

Security hardening 008 and Phase 1 were applied previously. New migrations are
local files only; **Phase 2 and Phase 3 have not been applied to the live DB**.
Review and authorize them in this order:

1. `supabase/migrations/20261004073859_phase2_pre_activity_compliance.sql`:
   staff evidence fields and logistics/personnel/vehicle/document tables.
2. `supabase/migrations/20261004124658_phase3_execution_and_closure.sql`:
   completion metadata, participant mode, closure document kinds and parallel
   activities with composite event/participant FKs, indexes and constraints.

New tables enable RLS and revoke client/public privileges; the backend-only
`smartevent_app` role is granted access. Existing approvals are preserved. The
historical local/remote migration lists are not baselined; do not blindly run
`db push` or repeat previously applied scripts. The new backend models need both
migrations before using the new event module against the real database.

## Verification and deployment limits

- Phase 2/3 cases in the full regression: **47 passed** (27 + 20).
- Full backend regression: **389 passed**, with four existing deprecation warnings.
- Flutter workflow tests: **9 passed** (login/logout, JWT use, PDF content type,
  uploads/versions, stale session, Officer restrictions, phone-layout roster
  correction and final Signatory exit).
- Isolated PostgreSQL/PGlite migration smoke: both phases passed, including
  historical preservation, constraints, cross-event FKs and RLS/client grants.
- Synthetic attendance: **53 sample participants across 4 A4 pages**; every
  rendered page inspected for wrapping, margins, repeated headings and signatures.
- Dart analysis of app `lib` and `test`, then the full Flutter project:
  **no issues found**; new files are formatted.
- Android debug APK: **build passed** on 4 October 2026. Artifact:
  `../build/app/outputs/flutter-apk/app-debug.apk`, including x86_64 emulator code.
- Android `:app:lintDebug`: **0 errors, 1 warning**. Fixed an invalid XML comment
  and declared camera hardware optional. `android/lint.xml` ignores only
  `PropertyEscape` for Flutter-generated `local.properties`: Flutter regenerates
  the valid SDK paths with literal drive-letter colons on each build. Other lint
  checks remain active. The remaining warning concerns a redundant `drawable-v21`
  qualifier; its splash-screen appearance was preserved.
- Local IDE content roots, Dart SDK library, Gradle linkage/JDK and tooling
  exclusions were repaired. The large exported `index.html` inspection report
  was excluded, not deleted. At the last check, Android Studio still needed its
  Flutter plugin installed and a restart/re-sync; the original 188-error IDE
  inspection count has not been independently rechecked.
- No Android device was connected during verification. The `Medium_Phone` AVD
  exists but was not launched. Native printing/sharing, live storage and the
  end-to-end event workflow remain unverified; check them after approved rollout.

Flutter SDK was temporarily provisioned under ignored backend `tmp/flutter-sdk`
for validation. Package resolution completed, but Windows plugin setup reports
Developer Mode disabled. Widget tests run; a native Windows build was not verified
and no system setting was changed. No production migration, key rotation or
external deployment was performed during implementation.

Read-only rollout check on 4 October 2026 confirmed that the configured live
database matches the inspected project: Phase 1's `requirement_presets` exists,
but Phase 2 tables and Phase 3 completion/participation fields are still absent.
The local backend was not listening on port 8000. See the Flutter project's
`../README.md` for Android Studio, emulator and backend startup instructions.
