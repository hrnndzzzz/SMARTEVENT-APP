# Offline viewing

## Accepted scope

Android/iOS read-only access to all regular records allowed by the signed-in
account. Automatically prepare records, details, files, current/default reports
and report combinations viewed online. SQLite holds response snapshots; private
files hold downloaded bytes. Offline viewing survives restart and token expiry
until explicit sign-out. Account administration remains online-only.

## Implementation tasks

1. Add the persistent snapshot store and deterministic offline filtering. Verify
   reopen, account isolation, partial data, files and invalidation with SQLite tests.
2. Integrate cache-aware API reads, guarded mutations, verified session restoration
   and a resumable foreground download coordinator. Verify transport failures,
   expired sessions, logout races, pagination and never-opened details.
3. Wire persistent download/freshness UI, local images/documents and read-only
   actions/SAP viewing. Verify no draft creation or notification writes offline.
4. Run analysis, Flutter tests/build, then independent review and fix regressions.

## Invariants

- Partition by server, user and verified role/department/organization.
- Never persist passwords, authorization headers or signed URLs in snapshots.
- Clear account data on explicit logout/account/server switch; reject late results.
- A health response alone never enables writes. Revalidate the profile first.
- API 401 retains the saved viewer but requires sign-in for server activity.
  The backend uses the same 401 for expired tokens and suspended users; cached
  access cannot distinguish these. Explicit account denial removes access.
- Server financial figures remain authoritative; no local recalculation.
- Empty, incomplete, denied and unavailable data are different states.
- Prepare using GET only. Never call the SAP fetch-or-create form loader.
- Three concurrent requests maximum; foreground only, any working connection.
- Keep old data on interruption/storage failure; never falsely claim full readiness.
- No offline edits, queued mutations, new signatory workflows or backend migrations.
- Existing PDF preview/share-to-device-viewer flow is reused.

## Verification

Automated tests cover persistence, filters, >100 notifications, stale reads,
expired tokens, API mutation guards, account/server/logout races and offline SAP.
Run Flutter analysis and the normal test suite. Build Android. Device acceptance:
prepare online, terminate, airplane mode, reopen details/files; repeat with server
stopped but internet available, then reconnect and reauthenticate. iOS validation
requires macOS/device tooling if unavailable on the implementation host.

## Using offline viewing

Sign in online once and keep the app in the foreground while the banner prepares
copies. Previously unopened records, supporting files and default PDFs are
included. A partial download remains usable; Retry resumes preparation.

On later launches, the saved viewer opens before the server check completes.
Changes remain unavailable until the account is verified online. An expired token
keeps the saved viewer and offers Sign in to refresh. Saved data dates lists the
oldest opened copy for each area, rather than treating all partial data as fresh.

Explicit sign-out or changing servers clears the saved account. A verified account
or permission-scope change clears the preceding scope and closes old detail routes.
PDFs and images use the existing device sharing/viewing flow.

## Review decisions and boundaries

- The independent review found scope-response races, denied-file retention,
  dropped foreground resumes and missing PDFs for previously viewed financial
  filters. These have regression coverage and were fixed.
- Per-area saved dates were treated as required freshness information and added.
- Mandatory-password-change refusals clear a previously saved viewer, including
  the less common case where the account was previously usable.
- New signatory features and account-administration caching remain excluded.
- Event-filtered inventory movement queries are not projected locally: no current
  screen sends that filter. A future caller must download that exact query first.
- Physical airplane-mode/restart acceptance and iOS compilation remain separate
  device checks; a successful Android build and mocked HTTP tests do not prove them.
