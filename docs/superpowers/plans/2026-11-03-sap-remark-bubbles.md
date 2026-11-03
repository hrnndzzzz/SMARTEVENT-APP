# SDS Remarks as Comment Bubbles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The SDS Office's remarks leave the SDS Coordinator's signature box. The printed form comes in two versions: **without comments** (the clean official form) and **with comments** (the same form, with each remark as a Word comment bubble in the margin beside the part it is about).

**Architecture:** `fill_form` stops writing remarks into Part 5. With `comments=True` it anchors one Word comment per remark (python-docx 1.2 `add_comment`), and Word exports that document "with markup", which puts the bubbles in a right margin. `GET /pdf` gains `comments=true`. The app's Print asks which version when the proposal has SDS remarks. The signatories' printout and the stored signed copy stay without comments.

**Tech Stack:** FastAPI, python-docx 1.2, Word via PowerShell COM (`ExportAsFixedFormat`, item 7 = with markup), pytest; Flutter app (Brut design system), flutter_test with `MockClient`.

**Spec:** this plan carries the design. It follows the approved mockup `SDS-remarks-mockup.pdf` (Option B, pages 7–11) and the user's ruling "two print options, one with comments and one without".

## Global Constraints

- Branch: one new branch `SDS-Remarks-Comments` from `develop` (b7ef17b), holding the backend and the app, pushed by name. A pull request goes to `develop`; nothing is pushed to `develop` directly.
- Commits: conventional subject, prose body saying what a user saw and why. No `Co-Authored-By` or "Generated with" lines.
- Backend tests: from `smartevent-backend/`, `DATABASE_URL="sqlite:///:memory:" JWT_SECRET_KEY="<32+ chars>" "C:/Users/hrnnd/Documents/thesis/SMARTEVENT-APP - Copy/smartevent-backend/.venv/Scripts/python.exe" -m pytest -q -p no:cacheprovider app`. Word renders real PDFs; a flaky "Could not convert the SAP form to PDF" is rerun once.
- App tests: `& "C:\Users\hrnnd\flutter-smartevent\bin\flutter.bat" test --no-pub <files>`; then `git checkout -- linux macos windows`.
- Design: reuse the app's Brut widgets and tones. The choice is offered the way the app already asks a two-way question (an `AlertDialog` or bottom sheet as in the SAP screens), no new look.
- Remarks text never prints under the signature in either version, for every outcome (signed, returned, rejected).

**Where each remark's bubble anchors** (the section remark keys are fixed by the backend):

| Remark | Anchored on |
|---|---|
| overall | the "Part 4: SDS Office Clearance" heading |
| `activity_details` | the "Activity Title:" label (Part 1) |
| `budget` | the "Budget:" label (Part 1) |
| `support_requests` | the "Part 2: School Support (Requests)" heading |
| `additional_information` | the "Part 3: Additional Information" heading |
| `clearance` | the "Part 4: SDS Office Clearance" heading |
| `other` | the "Part 4: SDS Office Clearance" heading |

Each comment's author is "SDS Office" with initials "SDS". The text is the remark, with "Overall: " in front of the overall one. Word labels each bubble "Commented [SDS1]:" and so on, which is Word's own and stays.

## Review Focus

1. Without comments, a reviewed proposal's PDF carries no remark text anywhere, and the signature box holds only signature, name and title.
2. With comments, every saved remark appears exactly once, beside its anchor; a remark whose anchor is missing falls back to the Part 4 heading instead of being dropped.
3. A proposal with no remarks gets the same PDF either way (no empty markup margin).
4. The signatories' printout and the final-scan page-count check use the version without comments.
5. Asking for comments on a signed revision does not change the stored signed copy or its SHA-256.

---

### Task 1: The form can carry its remarks as comments

**Files:** `smartevent-backend/app/services/sap_pdf.py` (`fill_form` :213-318, `_remarks` :345, `_WORD_SCRIPT` :365-374, `docx_to_pdf` :385, `render_proposal` :427), `smartevent-backend/app/test_sap_docx.py`.

**Interfaces — produces:** `fill_form(snapshot, *, review=None, signer_name=None, signature_strokes=None, signed=False, comments=False) -> bytes`; `docx_to_pdf(docx, *, markup=False) -> bytes`; `render_proposal(..., comments=False)`. With `comments=True` and at least one remark, `render_proposal` converts with `markup=True`.

- [ ] Failing tests:
  - `test_remarks_never_sit_under_the_signature`: with a review holding overall and section remarks, signed and unsigned, the "SDS Coordinator" cell contains no remark text, and `comments=False` leaves no `word/comments.xml` part.
  - `test_each_remark_becomes_a_comment_beside_its_part`: `comments=True` with all six section keys plus overall gives seven comments, each by "SDS Office", and each anchored in the paragraph the table above names (assert on the anchored run's paragraph text).
  - `test_no_remarks_means_no_comments`: `comments=True` with an empty review gives no comments part.
  - `test_markup_export_asks_word_for_comments`: with `subprocess.run` mocked, `docx_to_pdf(b'..', markup=True)` passes a script containing `ExportAsFixedFormat` with item `7` and the markup view settings; `markup=False` keeps today's script.
- [ ] Implement:
  - Drop the remarks paragraph from the SDS Coordinator cell.
  - Add the comments with `Document.add_comment(runs, text=..., author='SDS Office', initials='SDS')`.
  - The markup script mirrors the mockup's: `View.Type = 3`, `ShowComments = $true`, `RevisionsFilter.Markup = 2`, `MarkupMode = 0`, `ExportAsFixedFormat(dst, 17, $false, 0, 0, 1, 1, 7)`, inside the same lock, timeout and process-kill handling as `_WORD_SCRIPT`.
- [ ] Pass: `pytest app/test_sap_docx.py`, plus one real render of each version (open both PDFs and look).
- [ ] Commit `feat(sap): print the SDS remarks as comments beside each part, not under the signature`.

### Task 2: The PDF route serves both versions

**Files:** `smartevent-backend/app/routers/sap.py` (`pdf` :382-397, `_printout` :44-53, signing :240-262), `smartevent-backend/app/test_sap.py`, `smartevent-backend/docs/sap-fo-020-frontend-contract.md`.

- [ ] Failing tests:
  - `GET /pdf` without the flag returns a PDF whose text has no remark.
  - `GET /pdf?comments=true` on a reviewed pending proposal returns a different PDF holding the remarks.
  - On a signed revision, `comments=false` returns the stored `signed_pdf` byte for byte, and `comments=true` renders a commented copy with the same signer, while the stored bytes and `signed_pdf_sha256` stay unchanged.
  - A returned and a rejected revision serve both versions, and the rejected one keeps its "REJECTED BY THE SDS OFFICE" mark in both.
  - The draft preview accepts the flag and, having no remarks, returns the same PDF.
- [ ] Implement:
  - Add a `comments: bool = False` query parameter, and add the flag to the `_printout` cache key.
  - A signed revision with comments renders from the stored review: remarks, `signature_strokes`, and the signer's name from `signed_by`.
  - Signing keeps storing the version without comments.
  - The filename gains `-comments` for the commented version.
  - Update the contract's `GET /pdf` row and the "A revision the SDS Office has signed prints…" paragraph.
- [ ] Pass: the full backend suite.
- [ ] Commit `feat(sap): let the printout be fetched with or without the SDS comments`.

### Task 3: The app asks which version to print

**Files:** `lib/api/sap_service.dart` (`pdf` :~419), `lib/state/sap_form.dart` (printout :~540-550), `lib/screens/sap/sap_form_screen.dart` (`_print` :48), `lib/screens/sap/sap_part5_screen.dart` (`_printForSignatories` :92, unchanged behaviour), tests: new `test/print_with_comments_test.dart`.

**Interfaces:** `SapService.pdf(String eventId, {int? revisionNo, bool withComments = false})` sends `comments=true` only when asked; `SapForm`'s printout method takes the same flag; `SapForm.hasSdsRemarks` is true when `sdsRemarkLines()` is not empty.

- [ ] Failing tests:
  - With SDS remarks saved, the hub's Print offers "Print with comments" and "Print without comments", and each requests `/pdf` with `comments=true` and without it respectively.
  - With no remarks, Print goes straight to the version without comments and offers no choice.
  - Part 5's "Print for the signatories" always requests the version without comments.
- [ ] Implement as in Interfaces. The choice reads: "With comments: the form with the SDS Office's remarks beside each part." and "Without comments: the clean form, as it goes to the signatories."
- [ ] Pass: the new test file, `test/printout_test.dart` and `test/final_scan_gate_test.dart`, then the full app suite.
- [ ] Commit `feat(sap): let the proposer print the form with or without the SDS comments`.

### Task 4: Full suites and push (controller)

- [ ] Run the backend suite and `flutter test --no-pub`, and `flutter analyze lib test` (no errors).
- [ ] Render a real reviewed proposal both ways and check the bubbles.
- [ ] Push `SDS-Remarks-Comments` by name, and give a prefilled compare link to `develop`.
