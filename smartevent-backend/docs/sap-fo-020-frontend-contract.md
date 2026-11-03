# SAS-SDS-FO-020 (001): backend and frontend contract

> For issue #9's current limits, budget fields and response schemas, see
> [the release handoff](SAP_ISSUE_9_HANDOFF.md). For the later SDS electronic
> signing and attachment flow, see [the implementation handoff](SAP_FRONTEND_IMPLEMENTATION_HANDOFF.md).
> Historical first-slice descriptions below do not override those additions.

## Authority and scope

This workflow tracks **nine physical signatures**, not electronic signatures.
An SDS action is an administrative record of inspected paper evidence, not a
signature made by the logged-in user. The uploaded final scan is authoritative
physical evidence; the server does not cryptographically authenticate handwriting.
SDS must compare the scan against the correct printed revision and signers.

First slice: on-campus and online activities; off-campus/CHED remains separate.
No changes to Flutter are included. Generic events retain their existing routing.
An existing generic draft can enter SAP only before any routing or approval history.
After conversion, generic edit/submit/delete/complete endpoints reject SAP events with
409, and so do approve/reject unless the proposal waits on department review (see
State and concurrency). Use this contract instead. Conversion back is not exposed.

All protected endpoints require the existing Bearer JWT, an active account and
password-change completion. Organization and department scopes remain enforced.
SDS is institution-wide, as its existing account role has no organization binding.

| Actor | Parts 1–3 | Part 4 | Record paper checkpoints / return / reject | Final scan | Part 6 |
|---|---|---|---|---|---|
| Original event proposer with treasurer/adviser/admin/super_admin role, or Officer holding President/Vice President/Secretary position | Draft or returned only | No | No | No | No |
| SDS staff | No | While `pending_sap_review` | Yes | Upload/read | Yes |
| Scoped operational readers/admins | Read | Read | Read history | No | Read |
| Other Officer positions | Read only | Read | Read history | No | Read |
| Signatory role alone | No new access | No | No | No | No |

Admin/super_admin does not override SDS-only permissions or proposer ownership.
Qualifying Officer positions can prepare and submit their own proposals, without
SDS review or signing powers. The preparation attestation identifies the original
proposer account; institutional onboarding must assign its correct role and position.
Do not create a treasurer-owned event if a different president must fill slot 1.
High-level physical signers need not have accounts.

## State and concurrency

`draft -> pending_department_review -> pending_sap_review -> approved -> completed`

Sending goes to the department before the SDS Office. The Moderator (event
`pending_adviser`) and then the Dean (event `pending_admin`) each decide it with
`POST /events/{event_id}/approve` or `/reject`, sending `{remarks, expected_version}`.
`expected_version` is optional, but send the `version` of the last response: a
proposal that has changed since (taken back and sent again, say) answers 409
`Proposal changed; reload before retrying`, checked before whose turn it is. Other
events and expenses ignore it. The Dean's
approval makes it `pending_sap_review`. A proposal that a Moderator sent or created
starts with the Dean. A return needs remarks, puts the proposal in
`revision_requested` and sets `returned_by` to `moderator` or `dean`. The SDS Office
sees a proposal only from the Dean's approval on, or after returning it itself; until
then its requests for it answer 403.

`revision_requested -> pending_department_review`, whoever returned it, creates a new
revision on resubmission. Returning requires a comment. The old PDF, snapshot and
recorded checkpoints remain unchanged. Never copy old signatures to a new revision.

The SDS Office decides a `pending_sap_review` proposal one of three ways: sign it
(`sds_signed`; see the implementation handoff), return it (`revision_requested`), or
reject it (`rejected`). `rejected` is final. `POST /sds-reject` takes the body of
`/return`, with nonblank remarks, and answers 409 in any other state it sees. The
proposal and its event become `rejected`; the remarks are saved as
`sds_review.overall_remarks`, and `returned_by` and `return_remarks` stay empty, since
a rejection is not a return. Nothing follows it: the proposer's edits, resubmission
and withdrawal, the SDS Office's further decisions and checkpoints, and the
department's approve and reject all answer 409.

The mutable proposal has `version` (optimistic edit version) and `revision_no`
(submitted revision, initially 0). Every mutation except initial creation supplies
`expected_version` from the last response. After a 409 reload; never blindly retry.
Every writer locks the parent event, so concurrent moderator writes serialize;
their **business order** remains parallel, but a stale screen must refresh.

Collection replacement or Part 1–3 editing clears SDS clearance. The proposer
submits Parts 1–3 without Part 4; SDS fills Part 4 while the revision is
`pending_sap_review` and must complete it before `/sds-sign` (422 otherwise).
In any other state it sees, `PUT /sds-clearance` answers 409 `Part 4 is filled in
while the SDS Office reviews the proposal`: a return clears Part 4, and the SDS Office
fills it in again once the next revision reaches it.
The signed PDF records it, since submitted revisions are immutable. Drafts allow
partial detail saves. Cross-field time, class and budget checks run at submission;
saving a draft is not clearance.

Event projection: draft/returned -> event `draft`; Moderator review ->
`pending_adviser`; Dean review -> `pending_admin`; SDS review ->
`pending_institutional_review`; rejected by the SDS Office -> `rejected`; evidence
accepted -> `approved`; evaluated -> `completed`. SAP stages are not added to the
existing EventStatus enum.
Submission synchronizes title, rationale/description, date, start/end times,
school year, scope and `estimated_cost`. **Allocated and remaining money are not
silently rewritten.** Complete draft detail saves also synchronize these fields,
invalidating prior compliance clearance when schedule or location changes. Correct
and reverify existing student evidence while the proposal is a draft, returned, or
with the Moderator or the Dean; submission, the Dean's approval and final approval
each require pre-activity readiness, so a 409 on the Dean's approval means the
evidence needs repair first. Set the event allocation before creating SAP; proposed total
cannot exceed it. Actual expenses are never proposal budget lines.

## Endpoints

Base: `/events/{event_id}/sap-proposal`. UUID path identifiers.

| Method and suffix | Body / query | Result |
|---|---|---|
| POST base | No body | 201 draft aggregate |
| GET base | None | Current working aggregate and evaluation |
| PATCH base | `{expected_version, details: {...partial fields}}` | Updated aggregate |
| PUT `/program-flow` | `{expected_version, items: [...]}` | Replace entire collection |
| PUT `/budget-items` | Same | Replace entire collection |
| PUT `/support-requests` | Same | Replace entire collection |
| PUT `/affected-classes` | Same | Replace entire collection; empty list clears it |
| PUT `/sds-clearance` | `{expected_version, clearance: {...}}` | SDS fills Part 4 while `pending_sap_review`; 409 in any other state it sees |
| POST `/submit` | `{expected_version}` | Freeze snapshot/PDF; create all nine checkpoints |
| POST `/withdraw` | `{expected_version}` | The proposer, or a colleague who may also propose in the event's organization (an admin only their own), takes the proposal back while it waits on the department or the SDS Office, until SDS review has started; returns to draft and clears Part 4 |
| GET `/workflow` | None | Current revision's nine-step progress |
| POST `/workflow/{step_id}/record` | Checkpoint body below | Updated workflow |
| POST `/return` | `{expected_version, remarks, section_remarks?}` | Return with nonblank remarks of up to 3000 characters (`/revise` keeps 1000); sets `returned_by: sds`. Omitted or `null` `section_remarks` keeps the saved ones; an object replaces them (keys and limits as in the implementation handoff) |
| POST `/sds-reject` | Same as `/return` | Reject a pending proposal for good; aggregate in `rejected` |
| GET `/pdf` | Optional `revision_no` >= 1, `comments` (default false) | Authenticated PDF attachment; `comments=true` adds the SDS remarks as margin comments (file name ends `-comments`) |
| POST `/final-signed-copy` | Multipart `expected_version`, `file` | 201 approved aggregate |
| GET `/final-signed-copy` | None; SDS only | Short-lived private URL + SHA-256 |
| POST `/evaluation` | `{expected_version, outcome, remarks}` | Completed aggregate |
| GET `/sap/verify/{token}` | Public; not nested under base | Minimal verification JSON |

Unknown JSON fields are rejected. Collection maximum is 16 items each, subject
to actual six-page fit. A 422 overflow error requires shortening content, not
silently omitting rows or adding uncontrolled pages. No collection row append API:
the client edits locally then sends the full list with the current version.

Example partial draft:

```json
{"expected_version": 2, "details": {"title": "Hack the Future", "expected_students": 145}}
```

Example program and budget replacements (send to their respective endpoints):

```json
{"expected_version": 3, "items": [{"start":"08:00:00","end":"11:00:00","activity":"Cybersecurity seminar"}]}
```

```json
{"expected_version": 4, "items": [
  {"particulars":"Speaker","amount":"2000.00"},
  {"particulars":"Certificates","amount":"300.00"},
  {"particulars":"Materials","amount":"200.00"}
]}
```

Send decimal money strings, not client floating-point sums. All times are local
Asia/Manila, 24-hour `HH:MM:SS`, without offsets. Activities are same-day; midnight
is `00:00:00`, noon is `12:00:00`. Overnight events need a later workflow extension.

## Field mapping: all six parts

The authoritative machine-readable schemas live in `app/schemas_sap.py`; development
OpenAPI also describes request schemas and field limits.

| Form area | JSON field(s) | Rules |
|---|---|---|
| Control/header | `form_code`, `form_version`, `revision_no` | Server-owned; 020 / 001 |
| School year / department / proposal date | `details.school_year`, `department_type`, `department`, `proposal_date` | School year validated with existing service |
| Off-campus agreement | Derived Not Applicable | `off_campus` rejected; no global 30-day rule |
| Part 1 title, organization, course | `title`, `organization_name`, `course` | Organization/department labels drive signature position display; no hardcoded ACPES names |
| Date / time | `activity_date`, `start_time`, `end_time` | End > start, proposal date <= activity date |
| Modality | `modality` | `face_to_face`, `online`, `hybrid` |
| Setting / venue | `setting`, `venue` | `on_campus`, `online`; online requires online modality |
| PIC / attire | `persons_in_charge`, `attire` | Summary fields; existing event personnel remain separate authoritative roster |
| Type / scope / program | `activity_types[]`, `scope`, `program_types[]` | Types are bounded labels; scope follows existing `departmental`/`organizational` enum |
| Students | `expected_students` | Positive expected count, not fabricated participant records |
| Rationale / objectives | `rationale`, `objectives` | Required by submission; bounded text |
| Values | `core_values[]` | courage, compassion, community_oriented, humility, interiority, missionary_spirit |
| EGAs | `egas[]` | Integers 1–4 |
| Program flow | `program-flow[].start/end/activity` | Required; each row inside activity window |
| Safety | `emergency_plan` | Required |
| Money | `total_budget`, `funding_source`, `budget-items[].particulars/amount` | Exact decimal equality, nonnegative; total <= allocated event budget |
| Part 2 support | `support-requests[].type/quantity/specify` | Types: budget, vehicle, food, room, sound, microphone, projector, chairs, tables, diverse_needs, other |
| Part 3 text | `additional_information`, `excuse_arrangement` | No automatic letter issuance in this backend slice |
| Affected classes | `affected-classes[].year_level/subject/class_date/start/end/professor` | Must overlap activity on the same date; manually declared, no school-wide timetable inference |
| Part 4 consent | `clearance.parents_consent`, `parents_consent_reason` | yes/not_applicable; NA requires reason |
| Attachments | `clearance.attachments` | Required descriptive summary; actual private evidence stays in existing compliance storage |
| Class interruption | `class_interruption`, `class_interruption_remarks` | yes/none; yes requires remarks and affected classes; none requires no affected classes |
| Medical exam | `medical_exam`, `medical_exam_reason` | yes/not_applicable; NA requires reason |
| Report of Compliance | `report_of_compliance`, `report_of_compliance_reason` | yes/not_applicable; NA requires reason |
| Ratio | `student_personnel_ratio` | SDS declaration; no off-campus 1:50 enforcement in this workflow |
| Part 5 | Workflow step evidence below | SDS-only paper checkpoint recording |
| Part 6 | `evaluation.outcome/remarks/evaluated_by/evaluated_at` | conducted/canceled, nonblank remarks, actor/time generated by server |

All detail keys in this table belong inside `details` unless a collection,
clearance, evaluation or server-owned field is explicitly named.

Example SDS clearance:

```json
{"expected_version":8,"clearance":{
  "parents_consent":"not_applicable","parents_consent_reason":"Online activity",
  "attachments":"Program flow and budget",
  "class_interruption":"yes","class_interruption_remarks":"Excuse letters required",
  "medical_exam":"not_applicable","medical_exam_reason":"Online activity",
  "report_of_compliance":"not_applicable","report_of_compliance_reason":"No off-campus travel",
  "student_personnel_ratio":"145:3"
}}
```

## Nine slots and workflow response

1. Organization President — Prepared by (original proposer preparation attestation).
2. Organization Moderator — Reviewed by.
3. College Dean — Reviewed by (required parallel pair with slot 2).
4. SDS Coordinator/Activity Officer — Reviewed by.
5. Director, SAS — Noted by.
6. Assistant VPAA — Endorsed by.
7. VPAA — Recommending Approval.
8. Applicable admins — Recommending Approval.
9. University President — Approved by.

For the fixture these render as ACPES President, ACPES Moderator and CITE Dean.
All nine must be distinct people. SDS supplies an institutional person
reference even when no app account exists; stable references prevent accidental
reuse. If an account is supplied its name must match and it must be active.
Slot 1 must link the original proposer account. Slots 2–9 prohibit that proposer.
Slot 1 is recorded first, slots 2 and 3 in either order, and each later slot only
after every slot before it. Physical date must be between submission's Manila date
and today and must not precede prerequisite signatures. Slots 1–4 can be recorded
from `pending_sap_review`. Slots 5–9 (Director, SAS onward) are recorded, and
`actionable`, only once the SDS Office has signed (`sds_signed`); recording one
earlier answers 409 `Slots 5 to 9 are signed after the SDS Office signs`. Incorrectly
recorded evidence is not overwritten: return the pending proposal and create a fresh
revision.

```json
{"expected_version":10,"signer_name":"Physical Signer Name",
 "signer_reference":"institution-person-002","assigned_user_id":null,
 "physical_signature_date":"2026-10-17","remarks":"Paper inspected by SDS",
 "recorded_on_behalf":true}
```

`recorded_on_behalf=false` requires the assigned signer account to equal the
recording SDS account. It still does not create an electronic signature.

Workflow shape (one of nine rows shown):

```json
{"state":"pending_sap_review","revision_no":1,"version":11,
 "completed_count":1,"total_count":9,"steps":[
  {"id":"<step UUID>","slot":2,"position":"ACPES Moderator",
   "display_label":"Reviewed by","revision_no":1,"status":"pending",
   "actionable":true,"evidence":null,"recorded_by":null,"recorded_at":null}
]}
```

Recorded rows have `status=recorded` and an `evidence` object containing the
checkpoint body minus expected_version. No steps exist until first submission.
Do not describe a recorded checkpoint as an in-app signed document.

## PDF, scan and QR behavior

`GET /pdf` returns draft preview when editable; otherwise it returns immutable
stored submission bytes. `?revision_no=1` retrieves that historical print copy.
The print template preserves six parts across six clean pages, has nine empty
physical signature slots, and never includes the scanned sample as a background.
Part 6 remains blank on the immutable pre-event print; evaluation is a separate
backend record. Draft previews have no verification QR; submitted copies do.

The SDS Office's remarks never print in the SDS Coordinator's cell. `GET /pdf?comments=true`
instead returns the form with each saved remark as a Word comment ("SDS Office") in the
margin beside its part: the Activity Title and Budget labels, the Part 2, 3 and 4
headings, and the overall remark (prefixed `Overall:`) on Part 4; a remark whose label is
missing sits on the Part 4 heading. That holds for a returned, a signed and a rejected
revision. A proposal with no remarks prints the same either way. A
rejected one, while it is the proposal's current revision, also carries the red
watermark `REJECTED BY THE SDS OFFICE` and the footer `SAP revision N | Rejected by
SDS`; earlier revisions print as they were. `GET /sap/verify/{token}` reports the
rejected current revision as `approval_state: rejected` with `approved: false`.

A revision the SDS Office has signed prints as the copy stored at signing, without comments (`comments=true` draws a separate commented copy from the stored review and signature; the stored copy and its SHA-256 never change): the
signer's name and drawn signature in the SDS Coordinator's cell, the red watermark
`SIGNED AND APPROVED BY SDS OFFICE` on every page and the footer `SAP revision N |
SDS signed`. It still does after approval. A revision that is neither signed nor the
rejected current one prints with the footer `SAP revision N | Unsigned` and no
watermark. On every copy the other signature slots print empty, and none of these
marks is a physical signature: download the private final scan for that evidence.

Final upload accepts at most 10 MB, an unencrypted PDF of at least three pages and the
same page count as the SDS-signed copy (the form and its addenda; otherwise 422), no
active forms/actions/annotations/embedded attachments. Scan paper to a flattened PDF.
This is conservative validation, not malware scanning or handwriting recognition.
All nine checkpoints and existing pre-activity compliance readiness are required.
The final upload is write-once; replacement after approval is intentionally not
exposed. There is no automatic waiver of incomplete student compliance.

Generated artifacts reside in backend-only revision storage, with SHA-256;
final scans reuse the private proposal-letter bucket with unique, non-upsert paths.
Only authenticated SDS may request a signed scan URL (300 seconds). Never store
signed URLs or tokens in analytics, public logs or frontend persistent caches.

QR payload uses configured HTTPS `SAP_VERIFICATION_BASE_URL/{random-token}`.
Set the base to the public API `/sap/verify` route; never derive it from Host.
Verification requires no login and returns only proposal UUID, form/version,
revision, approval state, approved boolean and server verification time. No names,
title, consent/medical files, storage paths or signed URLs are exposed. Unknown
tokens return 404; superseded revisions are not approved. Responses are no-store.
The endpoint returns JSON; a branded frontend verification screen is future UI work.

## Evaluation and existing closeout

SDS evaluates an approved proposal once, with nonblank remarks. Conducted requires
activity date <= today and initializes the existing student learning-journal
requirements. Canceled records an explicit cancellation outcome; it does not invent
attendance, expenses, student journals or a new canceled event lifecycle status.
Both outcomes complete administration (`completed`) and preserve existing derived
`CLOSED` rules. Completion is not equivalent to conducted and does not automatically
waive closeout reports. Frontend analytics must read `evaluation.outcome` to
distinguish cancellation from conduct. Existing closeout staff permissions remain.

```json
{"expected_version":23,"outcome":"conducted","remarks":"Activity completed; reports to follow."}
```

## Notifications

Every SAP notice goes to the event's proposer and, once a revision exists, to
whoever sent that revision (a colleague may have sent what the proposer created;
nobody is told twice). Active, unsuspended SDS staff are told too, but only while the
proposal is or just was with the SDS Office: the Dean's approval, an SDS return,
rejection, signature, correction, checkpoint, final approval and evaluation, and a
withdrawal from the SDS Office. Sending, the department's return and a withdrawal
from the department do not reach them. The Moderator and the Dean get none as
reviewers. A rejection reads "SAP proposal rejected" with action `sap_rejected`.
The payload is described in
[the release handoff](SAP_ISSUE_9_HANDOFF.md#release-2-notifications).

## Errors and frontend recovery

- 401: missing/invalid authentication; use the normal login flow.
- 403: role, proposer ownership or organization restriction. Do not offer retry as another signer.
- 404: event/proposal/current checkpoint/revision/token unavailable.
- 409: stale version, wrong lifecycle state, incomplete predecessors/readiness,
  duplicate final evidence, or prohibited generic workflow operation. Reload state;
  compliance errors may provide `detail.message` plus `detail.blockers`.
- 422: invalid field/time/budget/class range, NA reason missing, malformed scan,
  or six-page template overflow. Keep the draft, show the error, let the user edit.
- 503: verification URL unconfigured, unavailable database or private storage.
  Do not display approved until the API confirms it. Reload before retrying uploads.

Validation `detail` may be a string, error array or structured blocker object.
Never assume a single shape. Example payload version numbers are illustrative;
always use actual server responses.

## Deployment and verification

Remote database status (October 18, 2026, Asia/Manila): applied successfully to
`SMARTEVENT: APP` (`vzdctweadahekptsmnyn`). Supabase recorded the exact local
`20261017000100_sap_fo_020.sql` contents as migration `20261018070927_sap_fo_020`.
Do not reapply the local file to this project. Reconcile this version mapping
before using CLI migration push; the remote tool assigned its own timestamp.

`supabase/tests/sap_access.sql` ran successfully against that remote project.
All six SAP tables have RLS enabled; backend grants and client access restrictions
passed; immutable-evidence triggers are enabled; `proposal-letters` is private.
These are database access/configuration checks, not an end-to-end API test or
a test of concurrent requests, signature authenticity, or signed-URL expiration.
The updated FastAPI server still needs to be running/deployed with dependencies
and a valid public `SAP_VERIFICATION_BASE_URL` before complete frontend testing.

1. Back up and apply `20261017000100_sap_fo_020.sql` after existing security and
   compliance phases 1–3 when setting up a new database, using the deployment
   owner. Already applied to the project above. It extends online logistics, adds
   nullable event time projections and recurring notifications, and creates
   server-only SAP tables plus immutable-evidence triggers.
2. Keep FastAPI on `smartevent_app`; anon/authenticated/service_role have no SAP
   table grants. SQL table owner/superuser credentials are not client credentials.
3. Install requirements including pinned pypdf. Configure the HTTPS verification
   base. Keep `proposal-letters` private and service credentials server-only.
4. Run the existing `python -m scripts.deliver_notifications` worker periodically.
   SAP uses the existing durable inbox/email queue; failures do not undo approval.
   Registration notification deduplication remains a partial unique index.
5. Run `python -m pytest -q`. SAP tests use isolated SQLite, mocked private uploads
   and a synthetic flattened PDF, never live files or real physical signatures.
6. Run the migration in disposable PostgreSQL staging and verify actual role/RLS,
   immutable triggers, concurrent requests and Supabase signed URL expiry before
   production. `supabase/tests/sap_access.sql` supplies read-only staging checks for
   RLS, table grants, immutable triggers and the default private bucket. It passed
   on the remote project above. Local SQLite tests do not execute PostgreSQL RLS.
7. Have SDS approve the clean printable layout and retention procedures. Pilot
   with paper signatures; do not treat a successful upload as signature verification.

The automated fixture covers October 28, 2026, online, 08:00–11:00, 145 students,
PHP 2,500 (2,000 + 300 + 200), two affected classes, an afternoon revision removing
those conflicts, nine checkpoints, scan upload and both evaluation outcomes.

Operational limits: failed storage/DB coordination can leave an unreferenced
private object (never an approved proposal). Reconcile orphans with an audited
retention job; never delete current evidence automatically. Production malware
scanning, automatic timetable import, off-campus rules, institutional scope beyond
the existing event enum, and electronic signatures are outside this slice.
