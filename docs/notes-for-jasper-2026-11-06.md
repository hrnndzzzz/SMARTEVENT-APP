# Notes for Jasper — 6 Nov 2026

## PR #29 — I checked the comment bubbles for you

Installed LibreOffice here and rendered a reviewed proposal both ways through
the real `soffice` path. **They work.** Margin boxes on pages 1 and 2, each
authored "SDS Office", each labelled with its section, dashed line to its part.

Checked properly, not just by eye:

- all seven remarks appear **exactly once** in the commented PDF
- **zero** of them appear in the clean version
- "SDS Office" appears 8 times vs 1 — seven attributions plus the Part 4
  heading, which is the only one left in the clean copy
- clean version is full width, no margin reserved, signature boxes empty
- `app/test_sap_docx.py`: 32 passed, 2 skipped (the Word PowerShell ones)

**Bigger thing: the whole backend suite now runs on macOS — 673 passed,
5 skipped, ~4 min.** Because `_USE_WORD = os.name == 'nt'` removed the Word
COM dependency. I can verify your backend work directly from now on instead
of relying on your test runs.

### Three things on the PR

1. **It's a blueprint, not a deployment.** Every URL in the README is still
   `https://<service>.onrender.com`. Nothing is live, so "where does the
   backend run for the defence" is answered on paper only.
2. **Free tier sleeps after ~15 min, ~1 min to wake.** You documented hitting
   `/health` beforehand, but a cold start mid-panel is a real risk. Worth
   deciding now whether we keep something pinging it during the defence.
3. **Branch is 7 commits behind develop**, conflicts on README only. It's also
   missing the deployed-build address guard from #30 — harmless, develop's
   side wins the merge, but merge develop in before it goes.

### One cosmetic thing

On page 2, where three comments share the Part 4 anchor, the dashed lines
cross each other and the "Additional information" box sits above the part it
points at. Still legible, but a panelist tracing a line could land on the
wrong box. LibreOffice stacks boxes in anchor order so it may not be cheap to
fix — not worth blocking the PR.

## Still outstanding from before

- **`receipt_number` and `issued_on` are never captured**, so `reference_key`
  is always null. The effect: the same paper receipt photographed twice is
  only *flagged* for review, never refused outright. The hard duplicate check
  is running on two of its three keys.
- **Four orphaned objects** in the receipts bucket, referenced by nothing.
- **Four expense rows with malformed `receipt_url`.**
- **`testofficer` and `testadviser` have no organization** and fail closed —
  they can't do anything.
- **`admin@smartevent.com` still has the `testpass123` password** that is
  committed in `SETUP.md`. That account is a super_admin on the live
  database, so anyone with the repo can sign in as it. Only you changing the
  password fixes this.
- Possibly delete **`example@email.com`** — a stray super_admin with position
  `string`, created from Swagger.

## Blocked on you

- **G16** — reports split by department/organisation needs the backend filter.
- The two rendered SAP PDFs for your comment bubbles — now verified above, so
  this one's cleared.
