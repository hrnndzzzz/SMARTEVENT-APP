# SAP Backend Handoff for the Frontend Team

**Status:** Backend SAP endpoints, storage metadata, review/signing flow, and form PDF generation are implemented in this change set. Frontend SAP screens and API integration remain for the frontend team. Migration/deployment and acceptance checks remain pending. No tests or builds were run, per request.

## What the backend now supports

- The supplied SAS-SDS-FO-020-001 V.3 Word form is stored under `app/templates/`; the PDF renderer fills its controlled three-page PDF layout and leaves non-SDS signatory lines available for hard-copy signatures.
- Draft SAP data, collection rows, clearance, submission, revision history, and physical signature checkpoints continue to use the existing event-scoped SAP API.
- Supporting documents are private, separately downloadable files. Categories are `apf`, `pcf`, `appendix`, `roc_coc`, and `other`. Each file is linked to the proposal revision it is intended for; the PDF lists file names, but does not merge the supporting files.
- Off-campus proposals must set `off_campus_agreement: true`, be submitted at least 30 calendar days before the activity using the server's institution date, and have a `roc_coc` attachment for that revision.
- SDS staff can save overall and section-specific remarks, return a proposal, or sign the current pending revision with a drawn signature. Remarks are printed on the form and overflow is added on a labeled remarks page.
- SDS signing stores signer identity, signature strokes, time, signed PDF bytes, and SHA-256 on the revision. The PDF carries a flattened `SIGNED AND APPROVED BY SDS OFFICE` watermark. The signed revision is locked; revisions after return/resubmission require a new signature.
- The existing physical signatory checkpoint flow remains separate. Final physical-signed scan approval now follows SDS signing.

## API contract

All routes below are nested under `/events/{eventId}/sap-proposal` and require an active authenticated account. Mutating calls use `expected_version` to protect against stale screens.

| Method and path | Access | Purpose |
|---|---|---|
| `POST /` | Authorized event proposer | Create a SAP proposal for a draft event. |
| `GET /` | Event-scoped user / SDS | Read proposal, version, state, attachments, review summary. |
| `PATCH /` | Authorized proposer, draft/returned | Update partial `details`; body includes `expected_version`. |
| `PUT /{collection}` | Authorized proposer, draft/returned | Replace `items` for `program-flow`, `budget-items`, `support-requests`, or `affected-classes`. |
| `POST /attachments` | Authorized proposer, draft/returned | Multipart form fields: `category`, `file`. PDF/JPEG/PNG, max 10 MB. |
| `GET /attachments` | Event-scoped user / SDS | List files for the active draft or current revision. |
| `GET /attachments/{attachmentId}/download` | Event-scoped user / SDS | Returns a short-lived private storage URL and SHA-256. Open/download this separately from the SAP PDF. |
| `PUT /sds-clearance` | SDS staff | Record clearance JSON for the draft. |
| `POST /submit` | Authorized proposer | Submit; server validates complete SAP, budget allocation, semester, 30-day rule, and off-campus ROC/COC. |
| `PUT /sds-review` | SDS staff, pending revision | Save remarks before signing. Body: `expected_version`, `overall_remarks`, and `section_remarks` map. |
| `POST /return` | SDS staff, pending revision | Return an unsigned revision with required `remarks`. |
| `POST /sds-sign` | SDS staff, pending revision | Sign with `expected_version`, optional remarks, and required normalized `signature_strokes`. |
| `GET /pdf?revision_no={n}` | Event-scoped user / SDS | Draft/current PDF. Returns stored signed PDF when the requested revision has been signed. |
| `GET /workflow` and `POST /workflow/{stepId}/record` | Event-scoped; record is SDS-only | Read and record the existing paper signatory checkpoints. |
| `POST /final-signed-copy` | SDS staff, SDS-signed revision | Upload the flattened hard-copy signature scan after required paper checkpoints. |

### SDS signature payload

```json
{
  "expected_version": 12,
  "overall_remarks": "Please revise the projected food budget.",
  "section_remarks": {"budget": "The meal estimate is above the allowable amount."},
  "signature_strokes": [
    [{"x": 0.08, "y": 0.7}, {"x": 0.3, "y": 0.25}, {"x": 0.6, "y": 0.5}]
  ]
}
```

Signature `x` and `y` coordinates are normalized from `0` through `1`. Use a canvas, capture strokes as a list of point lists, and keep each point to `{x, y}`. Successful signing changes state to `sds_signed`; fetch `/pdf` to download/print the locked PDF.

### Attachment categories

`apf` (Activity Proposal Form), `pcf` (Parent Consent Form), `appendix`, `roc_coc` (required for off-campus), and `other`. Upload each as its own multipart file. The backend accepts PDF, PNG, or JPEG up to 10 MB and returns attachment metadata in proposal responses. Supporting files are not embedded in the printable SAP PDF.

## States the UI should expect

`draft` → `pending_sap_review` → `sds_signed` → `approved` → `completed`.

SDS may return an unsigned pending revision to `revision_requested`; the proposer edits and resubmits, creating a new revision. The signed revision cannot be edited. Show the returned remarks and require refresh before retrying any write that receives HTTP `409` (stale version or invalid state).

## Frontend work still needed

- Add a SAP proposal entry point and form UI with collections and off-campus agreement.
- Add multiple supporting-file selection/upload, attachment listing, and separate download/open actions.
- Add SDS review UI with remarks, return action, and drawn signature pad; after signing, offer the signed PDF for print/share.
- Keep physical signature collection/checkpoint actions distinct from the SDS e-signature.

## Deployment notes

Apply migration `20261022000100_sap_review_signature_attachments.sql` before deploying the API. Configure the existing private proposal-letter storage bucket and SAP verification URL as for the prior SAP API. The app stores a canonical PDF hash; a downloaded copy can still be modified outside the app.
