# SAP PDF visual check - 23 October 2026

Status: NOT print-ready.

## Executed

- Read-only lookup of the configured database found one SAP proposal: a draft with empty details. Its PDF request returned HTTP 422 for missing required fields. No live data was changed.
- An isolated API test populated a complete sample, submitted it, saved SDS remarks, downloaded the unsigned PDF, applied a synthetic SDS signature, and downloaded the signed PDF. The test passed.
- Both generated PDFs contained four pages. All eight pages were rendered and visually inspected.
- Sample content, budget, affected classes, remarks, signature, and watermark were present. Other signatory areas remained available.

## Findings

1. Field positions overlap table borders: title, organization, course, venue, emergency plan, and budget/source fields need coordinate corrections. Verification footer also intersects the template footer line.
2. Checkbox positions/mapping need correction. A class-interruption value of yes appears beside None. Other clearance/core-value marks overlap printed labels. Program and activity categories are not reliably matched to the official choices.
3. The SDS watermark renders as opaque red and obscures form content. It must remain readable without obscuring the underlying form.

## Limits

This tests the backend API workflow, not Flutter screen interaction. The exact filled form the user sees could not be checked because the configured backend has no populated saved SAP details. The sample PDFs are diagnostic artifacts, not approved print copies. No application code was changed or pushed during this check.

Next: correct the renderer coordinates, checkbox mapping, and watermark appearance; rerender and repeat visual inspection before declaring print readiness.

## Recheck - 26 October 2026

Status: findings 1-3 fixed in `app/services/sap_pdf.py`; ready for a print test on paper.

- Rendered the `test_sap.fixture_data()` sample, changed to off campus, face to face, three program types (two official, one "Others"), two activity types, four scope options, and quantity/unit cost on every budget line. Rendered unsigned and SDS-signed; all four pages of each were inspected.
- Fields sit inside their cells, and the footer clears the template line. Department, off-campus agreement, setting, modality, activity type, program, core values, EGAs and the Part 4 clearance ticks land in their own brackets. A program type with no official box ticks "Others" and is written beside it.
- The signed watermark is translucent and the form reads through it.
- The budget breakdown addendum is a table: particulars, quantity, unit cost and amount.
- Fixed during this recheck: the second scope column (Institutional, National) ticked beside the option instead of inside it, and the time touched the left border of its cell.

Not checked: a real paper print, and a proposal saved through the app (still none with full details in the configured database).
