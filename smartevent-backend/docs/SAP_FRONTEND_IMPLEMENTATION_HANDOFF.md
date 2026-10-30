# SAP backend and frontend handoff

Updated: 30 October 2026.

## Current progress

The backend fixes cover Python syntax, PDF overflow, returned remarks, signed-revision corrections, validated supporting files, upload concurrency, and PDF query size.

The Flutter SAP form now has an **SDS review and signature** screen with overall/section remarks, a signature pad, PDF sharing, and a correction action. It recognizes **sds_signed** and enables the final scan only in that state. Existing proposal-entry screens remain in place.

Validation: the full backend suite now passes: **452 passed, 0 failed** on 22 October 2026. See [Backend test report](BACKEND_TEST_REPORT.md) for module results and limitations. Live storage, deployed PostgreSQL migrations/policies, and visual print layout remain unverified. Prior targeted Dart analysis reported an unresolved local file_picker package; frontend work belongs to the separate frontend team.

## State and revision rules

- Proposer edits are allowed in **draft** and **revision_requested**.
- Submission creates an immutable revision and sets **pending_department_review**. The Moderator, then the Dean, approve or return it with **POST /events/{eventId}/approve** and **/reject**; a return needs remarks and sets **returned_by** (moderator, dean or sds). The Dean's approval sets **pending_sap_review**.
- SDS can save notes, return the unsigned revision, or sign it.
- Signing sets **sds_signed**, stores the PDF, signer, time, strokes, and SHA-256, and locks the review.
- SDS can request a correction using **/revise** while the signed proposal awaits paper approval. The original signed bytes and hash stay in history. The next submission creates a new revision with no inherited signature or checkpoints.
- Final paper-scan approval follows SDS signing and all existing paper evidence checkpoints. Approved/completed proposals cannot use **/revise**.

All writes except proposal creation require **expected_version**. A 409 means reload and let the user review the current state before retrying. Do not automatically retry uploads.

## API routes

Base: **/events/{eventId}/sap-proposal**.

| Method / suffix | Access | Request / result |
| --- | --- | --- |
| POST base | Authorized proposer | Create SAP for a draft event. |
| GET base | Event scope or SDS | Current fields, version, attachments, and sds_review metadata. PDF bytes/strokes are not included. |
| PATCH base | Proposer, editable | expected_version, partial details. |
| PUT /{collection} | Proposer, editable | expected_version, items. Collections: program-flow, budget-items, support-requests, affected-classes. |
| PUT /sds-clearance | SDS, editable | Existing clearance payload. |
| POST /submit | Proposer, editable | expected_version. Complete form/compliance checks still apply. |
| POST /attachments | Proposer, editable | Multipart **expected_version, category, file**. Upload multiple files sequentially, using the version returned by each successful response. |
| GET /attachments | Event scope or SDS | Files for the active draft/current revision. Optional revision_no lists historical files. |
| GET /attachments/{id}/download | Event scope or SDS | Private URL, expiry, SHA-256. Download each supporting document separately. |
| PUT /sds-review | SDS, pending | expected_version, overall_remarks, section_remarks. |
| POST /return | SDS, pending | expected_version, nonblank remarks; keeps that revision unsigned. |
| POST /sds-sign | SDS, pending | expected_version, optional remarks, required signature_strokes. |
| POST /revise | SDS, signed | expected_version, nonblank remarks; starts an editable correction while retaining the signed revision. |
| GET /pdf | Event scope or SDS | Latest submitted/reviewed PDF, or a draft when nothing has been submitted. Signed revisions return their stored PDF. |
| GET /pdf?revision_no=1 | Event scope or SDS | Specific historical revision. |
| GET /pdf?draft=true | Event scope or SDS | Preview current editable changes. Cannot combine with revision_no or request on a locked proposal. |
| GET /workflow | Event scope or SDS | Existing paper evidence checkpoints. |
| POST /workflow/{id}/record | SDS | Existing physical evidence request. |
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

Returned unsigned proposals default to their reviewed revision, so comments remain visible. Use **draft=true** to preview edits. After correction of a signed revision, the historical signed PDF remains available; the new draft preview is unsigned and needs a fresh signature after resubmission.

## Remaining frontend integration

The signing/review fixes are wired from Event details → Proposal form → SDS review and signature.

The proposal upload UI still needs to consume the supporting-file endpoints, and the off-campus form controls must send the agreement and ROC/COC fields. These were not part of the targeted review-fix integration.

## Deployment

Apply the existing **20261022000100_sap_review_signature_attachments.sql** migration before deploying this feature if it is not already applied. These fixes introduce no additional database migration.

Keep the existing proposal-letter storage bucket private. Set SAP_VERIFICATION_BASE_URL as before. A stored hash protects the canonical app copy; downloaded PDFs can still be changed with external software.

This backend delivery includes the fixes and test report. Deployment and database migrations remain separate steps; no deployment or database mutation was performed during this repair pass.
