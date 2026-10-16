# Phase 2: pre-activity compliance and logistics

> Rollout update: this migration was applied to the live project on 5 October
> 2026 as `20261005105021_phase2_pre_activity_compliance`. Historical deployment
> and in-memory-session descriptions below predate the later Flutter integration.
> See `../FRONTEND_INTEGRATION.md` for current status.

Implemented locally 4 October 2026. The approved interface is inside the existing
Flutter app: Dashboard -> Events & compliance. It uses backend staff login and
protected APIs. The separate `/compliance-workspace` and its static files were
removed at the user's request; that endpoint now returns 404.

## Confirmed workflow

1. Create a draft with academic metadata and an activity date.
2. Explicitly classify it on-campus or off-campus and record the destination.
3. Admin/Super Admin records the student list, including spreadsheet paste.
   These students receive neither accounts nor a private upload portal.
4. Admins/Advisers configure requirements and assign qualified institution-employee PICs.
5. The proposer or Admin uploads logistics/government evidence. Admins/Advisers
   upload student evidence and verify uploaded files or batches of physical originals.
6. Submit the proposal through the existing Adviser/Admin workflow. Admin handoff
   requires readiness and an ordered institutional route; the last signatory checks
   readiness again before approval. Self-review and scope restrictions still apply.

An Adviser-created proposal starts at Admin review, preserving the existing rule.
Structure can change only while draft/rejected. Evidence may be collected through
pending Admin review. Institutional handoff freezes changes. Corrections require
rejection and resubmission. A changed date, destination, classification or transport
mode clears previous verification while retaining evidence files and audit history.

## Off-campus checks

- Active student roster; at least one qualified employee PIC, with at most 50
  participating students per PIC. Duplicate employee references cannot inflate the count.
- Required consent and medical-clearance presets; consent includes staff confirmation
  of notarization. Every required student document must be VERIFIED.
- Reviewed LGU coordination and concerned-agency acknowledgment files with references.
- Active vehicles: registration, insurance, driver license, roadworthiness evidence.
- Third-party vehicles additionally require LTFRB franchise and DOT accreditation
  evidence, plus an LTFRB special permit for an out-of-line trip.
- Staff confirms transport validity for the event date; known expiry before that
  date blocks verification and readiness. No-vehicle transport needs an explanation.

On-campus events do not require the transportation/LGU/PIC checks. Explicitly
configured required student documents still apply.

## Access and paper trail

| Role | Phase 2 access |
|---|---|
| Admin/Super Admin | Maintain participant roster; manage requirements/PICs/logistics; upload and verify evidence within existing scope. |
| Adviser | Read student records, assign PICs, upload and verify student/logistics evidence; manage own proposal logistics. |
| Treasurer | Manage own logistics and government/transport uploads; cannot read student medical files or verify paperwork. |
| Officer | Read readiness totals; no roster, medical files or Phase 2 writes. |
| Assigned Signatory | Read assigned pending-institutional event logistics and evidence, approve sequentially; no individual student records. |
| SDS Staff | No compliance access. |

Participant/PIC/vehicle withdrawal is soft deactivation. Drafts with compliance
records cannot be deleted. A roster identity with submitted/reviewed evidence
cannot be renamed to another student. Staff review records actor, time, remarks,
evidence mode and version. Stale uploads/reviews return 409; batch validation is atomic.
All writers and approval gates lock the parent event.

PDF/JPEG/PNG uploads are limited to 10 MB; images use the existing metadata-stripping
processor. Documents use private proposal-letter storage but are NOT proposal-letter
records, preventing SDS/general-letter access. ID-based file endpoints authorize
scope before issuing five-minute links; ordinary responses omit object references.
The Flutter module keeps tokens only in memory and clears displayed data at
logout; it also clears student data before refreshing authorization. Use HTTPS
in deployment. Signatory decisions that end institutional review return to the
event list, because that role no longer has access to the event detail.

## API entry points

Under `/events/{event_id}`:

| Path | Action |
|---|---|
| `/readiness` | GET counts and approval blockers. |
| `/logistics` | GET summary / PUT explicit classification and transport settings. |
| `/participants` | POST 1–500 students; PATCH `/{participant_id}` correct unsubmitted identity or activate/withdraw. |
| `/requirements` | POST pre-activity requirement; PATCH `/{requirement_id}` required/optional. |
| `/personnel`, `/vehicles` | POST assignment; PATCH `/{id}` activate/deactivate. |
| `/compliance` | GET staff participant/requirement checklist. |
| `/compliance/{record_id}/upload` | POST multipart file and expected version. |
| `/compliance/batch-review` | POST 1–100 record IDs/versions, decision, evidence mode, notarization and remarks. |
| `/compliance/{record_id}/file` | GET authorized student file link. |
| `/compliance-documents` | POST event/vehicle file, kind, reference, optional expiry and expected version (0 for new). |
| `/compliance-documents/{id}/review`, `/{id}/file` | POST staff decision / GET authorized link. |

## CHED interpretation

The primary reference is [CMO No. 63, s. 2017](https://ofa.upd.edu.ph/wp-content/uploads/2017/12/CHED-CMO-No-63-s.-2017-Policies-and-Guidelines-on-Local-Off-Campus-Activity.pdf),
listed on the [CHED 2017 memorandum index](https://legacy.ched.gov.ph/2017-ched-memorandum-orders/).
It describes institution-employee PIC qualifications, a 1:35–50 ratio for curricular
activities, transport documents, coordination and other institutional responsibilities.

The requested maximum of 50 is the implemented ceiling. Universal medical clearance
and DOT/LTFRB evidence for all third-party transport are the project's stricter
checklist; applicability in the memorandum varies by activity/provider. The app does
not decide legal exemptions, certify authenticity, reproduce official annexes or
cover every CHED duty. Orientation, insurance for participants/PICs, emergency planning,
curricular suitability and institutional certification still need institutional review.

## Migration and verification

Local migration: `supabase/migrations/20261004073859_phase2_pre_activity_compliance.sql`,
after security hardening 008 and Phase 1. It adds four server-only RLS-protected
tables and participant/evidence fields, retaining historical approvals. The prior
remote/local migration histories are not fully baselined; do not run an unreviewed
blanket `db push`.

Validation: 47 Phase 2/3 cases passed in the full 389-case backend regression
(27 Phase 2, 20 Phase 3).
Isolated PGlite PostgreSQL migration tests passed for constraints, legacy
preservation, composite FKs, RLS and backend/client privileges. Nine Flutter
workflow tests passed. Existing ReportLab/storage helpers were reused; no new
backend production dependency was added. Native Flutter picking/printing uses
`file_selector` and `printing`, with versions resolved in the app lockfile.
Storage upload/signing were mocked: these tests are not live storage/device QA.
See [Phase 3 handoff](PHASE_3_IMPLEMENTATION.md) for deployment boundaries.
