# SAP backend and frontend handoff

Updated: 31 October 2026.

## Current progress

The backend fixes cover Python syntax, PDF overflow, returned remarks, signed-revision corrections, validated supporting files, upload concurrency, and PDF query size.

The Flutter SAP form now has an **SDS review and signature** screen with overall/section remarks, a signature pad, PDF sharing, and a correction action. It recognizes **sds_signed** for printing, but its Part 5 final-scan upload still enables only in **pending_sap_review**. The server accepts the scan only in **sds_signed**, and slots 5 to 9 are recorded only after the signature, so that button never enables until the app changes (see Remaining frontend integration). Existing proposal-entry screens remain in place.

Validation: the full backend suite now passes: **452 passed, 0 failed** on 22 October 2026. See [Backend test report](BACKEND_TEST_REPORT.md) for module results and limitations. Live storage, deployed PostgreSQL migrations/policies, and visual print layout remain unverified. Prior targeted Dart analysis reported an unresolved local file_picker package; frontend work belongs to the separate frontend team.

## State and revision rules

- Proposer edits are allowed in **draft** and **revision_requested**.
- Submission creates an immutable revision and sets **pending_department_review**. The Moderator, then the Dean, approve or return it with **POST /events/{eventId}/approve** and **/reject**; a return needs remarks and sets **returned_by** (moderator, dean or sds). Send the proposal's **expected_version** with either; it is optional, and a proposal that has changed since answers 409. The Dean's approval sets **pending_sap_review**.
- SDS can save notes, then sign the revision, return it, or reject it.
- Signing sets **sds_signed**, stores the PDF, signer, time, strokes, and SHA-256, and locks the review.
- Rejecting with **/sds-reject** is final: the proposal and the event become **rejected**, the review keeps the remarks, and nothing can be edited, resubmitted, withdrawn or signed afterwards.
- Part 4 (**PUT /sds-clearance**) is filled in only while the proposal is **pending_sap_review**; any other state SDS sees, including after a return, answers 409. A return clears Part 4, and SDS fills it in again on the next revision.
- SDS can request a correction using **/revise** while the signed proposal awaits paper approval. The original signed bytes and hash stay in history. The next submission creates a new revision with no inherited signature or checkpoints.
- Paper checkpoints 1 to 4 can be recorded while the proposal is pending or signed; checkpoints 5 to 9 only once it is **sds_signed**, and they are not **actionable** before that.
- Final paper-scan approval follows SDS signing and all existing paper evidence checkpoints. Approved/completed proposals cannot use **/revise**.
- Every SAP notice goes to the event's proposer and, once a revision exists, to whoever sent that revision. SDS staff are told too only while the proposal is or just was with the SDS Office; the Moderator and the Dean get none as reviewers.

All writes except proposal creation require **expected_version**. A 409 means reload and let the user review the current state before retrying. Do not automatically retry uploads.

## API routes

Base: **/events/{eventId}/sap-proposal**.

| Method / suffix | Access | Request / result |
| --- | --- | --- |
| POST base | Authorized proposer | Create SAP for a draft event. |
| GET base | Event scope or SDS | Current fields, version, attachments, and sds_review metadata. PDF bytes/strokes are not included. |
| PATCH base | Proposer, editable | expected_version, partial details. |
| PUT /{collection} | Proposer, editable | expected_version, items. Collections: program-flow, budget-items, support-requests, affected-classes. |
| PUT /sds-clearance | SDS, pending | Existing clearance payload; 409 in any other state SDS sees. |
| POST /submit | Proposer, editable | expected_version. Complete form/compliance checks still apply. |
| POST /attachments | Proposer, editable | Multipart **expected_version, category, file**. Upload multiple files sequentially, using the version returned by each successful response. |
| GET /attachments | Event scope or SDS | Files for the active draft/current revision. Optional revision_no lists historical files. |
| GET /attachments/{id}/download | Event scope or SDS | Private URL, expiry, SHA-256. Download each supporting document separately. |
| PUT /sds-review | SDS, pending | expected_version, overall_remarks, section_remarks. |
| POST /return | SDS, pending | expected_version, nonblank remarks, optional section_remarks; keeps that revision unsigned. |
| POST /sds-reject | SDS, pending | Same body as /return; rejects the proposal for good. |
| POST /sds-sign | SDS, pending | expected_version, optional remarks, required signature_strokes. |
| POST /revise | SDS, signed | expected_version, nonblank remarks; starts an editable correction while retaining the signed revision. |
| GET /pdf | Event scope or SDS | Latest submitted/reviewed PDF, or a draft when nothing has been submitted. Signed revisions return their stored PDF. |
| GET /pdf?revision_no=1 | Event scope or SDS | Specific historical revision. |
| GET /pdf?draft=true | Event scope or SDS | Preview current editable changes. Cannot combine with revision_no or request on a locked proposal. |
| GET /workflow | Event scope or SDS | Existing paper evidence checkpoints. |
| POST /workflow/{id}/record | SDS | Existing physical evidence request. Slots 5 to 9 only once the proposal is signed. |
| POST /final-signed-copy | SDS, signed | Multipart expected_version, file; all checkpoints and every page of the signed PDF/addenda are required. |
| GET /final-signed-copy | SDS | Private final-scan download URL. |

### Remarks and signing

Section keys: activity_details, budget, support_requests, additional_information, clearance, other.

Overall remarks: maximum 3,000 characters. Each section remark: maximum 1,000. Explicit empty values clear notes; omitted values in the signing request retain saved notes.

~~~json
{
  "expected_version": 12,
  "overall_remarks": "Budget reviewed.",
  "section_remarks": {"budget": "Updated estimate accepted."},
  "signature_strokes": [
    [{"x": 0.08, "y": 0.7}, {"x": 0.3, "y": 0.25}, {"x": 0.6, "y": 0.5}]
  ]
}
~~~

Coordinates are normalized 0–1 from the signature pad's top-left corner. Maximum 80 strokes and 5,000 points. The server uses the authenticated SDS account name. Signing cannot succeed in the frontend's offline/local-only mode.

Return and reject send the overall remarks as **remarks** (1 to 3,000 characters, not blank) and may add **section_remarks** with the same keys and limit. The old body without **section_remarks** still works. As with signing, omitting **section_remarks** keeps the notes already saved; a return or rejection also keeps them on null (signing answers 422 for null). An object replaces them, and an empty one clears them. **/revise** keeps its own **remarks** limit of 1,000 characters.

### Supporting documents

Categories: apf, pcf, appendix, roc_coc, other.

Maximum 30 files per draft revision, 10 MB per incoming file. PDFs must be parseable, unencrypted, 1–100 pages, and free from the blocked active-content actions. PNG/JPEG images are decoded and normalized using the existing image helper; their returned hash describes the stored normalized bytes.

Uploads run in a worker thread. The database transaction is released before storage calls, and version/state are checked again under the event lock before linking the file. Failed writes attempt cleanup only after checking that the object was not committed.

Files belong to a particular revision. A returned/corrected draft starts with its next revision's uploads; old files remain accessible through the historical list. Upload required supporting files again for the corrected draft.

### Off-campus submission

Set setting to **off_campus** and off_campus_agreement to **true**. The active draft revision must have a roc_coc attachment. The activity must be at least 30 calendar days from the server's institution date; exactly 30 is accepted. Existing allocation, semester, SDS clearance, and compliance checks still apply. Uploading a document does not establish compliance by itself.

## PDF behavior

The official Word file and its three-page PDF remain controlled assets under app/templates/.

The renderer fills the original pages. Long fields and remarks move to labeled, paginated addenda; program flow, budget rows, support-request details, and affected classes are preserved in full. Addenda carry the revision/footer and, when signed, the SDS watermark. The SDS name/signature are confined to the SDS block; other signatories remain available for paper signing.

The SDS remarks (overall and by section) print in the SDS block for a returned, a signed and a rejected revision alike. A rejected proposal's current revision also carries the **REJECTED BY THE SDS OFFICE** watermark and the footer **Rejected by SDS**; earlier revisions print as they were.

Returned unsigned proposals default to their reviewed revision, so comments remain visible. Use **draft=true** to preview edits. After correction of a signed revision, the historical signed PDF remains available; the new draft preview is unsigned and needs a fresh signature after resubmission.

## Remaining frontend integration

The signing/review fixes are wired from Event details → Proposal form → SDS review and signature.

The proposal upload UI still needs to consume the supporting-file endpoints, and the off-campus form controls must send the agreement and ROC/COC fields. These were not part of the targeted review-fix integration.

The app also has to offer the SDS Office a Reject action (**/sds-reject**) and treat **rejected** as final, send the optional **section_remarks** with a return, and send **expected_version** with the Moderator's and the Dean's approve and reject of a proposal. It must also enable the Part 5 final-scan upload only in **sds_signed** (today it checks **pending_sap_review**) and the Part 4 "Confirm clearance" action only in **pending_sap_review** (today only the app's read-only flag gates it; the server answers 409 in any other state it sees), and show a rejected SAP event read-only, including its compliance and letter screens: the backend still lets those side records change, but they cannot reopen the proposal.

## Deployment

Apply the existing **20261022000100_sap_review_signature_attachments.sql** migration before deploying this feature if it is not already applied. These fixes introduce no additional database migration.

Keep the existing proposal-letter storage bucket private. Set SAP_VERIFICATION_BASE_URL as before. A stored hash protects the canonical app copy; downloaded PDFs can still be changed with external software.

This backend delivery includes the fixes and test report. Deployment and database migrations remain separate steps; no deployment or database mutation was performed during this repair pass.
