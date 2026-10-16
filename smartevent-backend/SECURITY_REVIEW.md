# Security review — 3 October 2026

Scope: all backend application code, maintenance scripts, dependencies and the
connected SMARTEVENT Supabase project's public-schema/storage security metadata.
The live review read catalogs and advisors, not user records. No live settings,
tables, files or credentials were changed.

## Live findings requiring rollout

| Finding | Evidence | Prepared fix |
|---|---|---|
| Critical: direct database exposure | 15 of 17 application tables have RLS disabled, including `users`, `otp_tokens` and `audit_logs`; `anon` has SELECT/INSERT/UPDATE/DELETE/TRUNCATE grants. | `008_security_hardening.sql` enables RLS and removes public-client grants. |
| Confidential receipt files are public | `receipts` bucket is public with a 50MB/image-wildcard allowance. | Make both buckets private, restrict MIME types/size, use authorized five-minute links. |
| Mutable database function lookup | Seven public trigger functions have no fixed search path. | Restrict execution and set trusted search paths in script 008. |
| New auth columns absent | Live `users` and `otp_tokens` lack attempt counters/lockout fields; a read-only application connection succeeds, but selecting the new fields fails with SQLSTATE `42703`. | Apply `repair_auth_schema.sql` for local authentication compatibility, or script 008 as part of the full rollout. |

All seven inspected public functions are security-invoker trigger functions; no
public views or security-definer functions were found. Both existing RLS tables
(`receipts`, `notifications`) have no policies; this denies ordinary Data API
access and does not protect the other 15 tables. The current `postgres` login
bypasses RLS and should be reserved for migrations.

Supabase advisor remediation: [RLS disabled](https://supabase.com/docs/guides/database/database-linter?lint=0013_rls_disabled_in_public),
[mutable search paths](https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable).
No assertion is made that the Data API was externally tested or data was leaked.

## Changes in this backend

- Login locks an account for 15 minutes after five failed attempts. Public auth
  routes permit 30 requests/minute/IP per worker. OTPs permit five guesses,
  expire, are replaced on resend, and have a 60-second account resend cooldown.
- Temporary passwords use 24 random bytes. Access tokens require subject,
  issue/expiry times, issuer and audience. Password changes/resets revoke prior
  tokens and all outstanding codes. New token claims invalidate old deployments'
  tokens; clients must log in again.
- Registration no longer returns roster personal data before verification.
  Verification reveals active status only to a holder of a valid code. Public
  registration still distinguishes roster eligibility; reset email delivery can
  reveal account existence through timing despite generic responses.
- Request bodies are capped at 12MB before parsing, including chunked requests.
  Files are capped at 10MB. Images are decoded, bounded by pixel count, resized
  and stripped of EXIF metadata. PDFs require a PDF header/end marker. OCR text,
  output and provider timeouts are bounded.
- Private upload paths bind organization and uploader. Transfers cannot reuse
  old organization's scans in new records. Existing evidence still requires
  record scope; external links never trigger server-side fetching.
- Stored file references stay stable. Authenticated `GET /files?reference=<url>`
  returns `url` and `expires_in: 300` after permission checks. Signing happens on
  demand in a worker thread, outside list serialization and mutation commits.
- Validation/provider/database failures redact secrets and submitted passwords.
  Responses use `no-store`, `nosniff` and `no-referrer`. Production hides API docs,
  requires explicit HTTPS origins, a 32-byte signing secret and verified DB TLS.
- Budget allocation changes preserve spent balances and cannot reduce funds
  below committed spending. Concurrent approvals and stock changes take row
  locks. Stock movements are applied only by the existing database trigger;
  duplicate manual updates that doubled stock were removed.
- Duplicate approval/PDF/image code and unused helpers/schemas were removed.
  Explanatory comments were reduced; security and deployment notes remain.

The authentication controls follow [OWASP authentication guidance](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
and [password recovery guidance](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html).

## Deployment order

1. Back up and test restoration. Test script 008 on staging PostgreSQL with the
   actual stock/budget triggers. SQLite regressions exercise a matching stock
   trigger but cannot certify PostgreSQL roles, policies or function privileges.
2. Resolve case-insensitive duplicate emails before the new unique indexes;
   retain legitimate accounts and their history. Confirm bucket IDs in script
   008 match configuration. The script requires an enabled stock movement
   trigger and fails transactionally if one is absent.
3. Apply script 008 as schema owner in a coordinated maintenance window. Existing
   receipt public URLs stop working when the bucket becomes private. Create a
   dedicated server LOGIN role with a private password and grant `smartevent_app`
   to it; do not grant ownership, BYPASSRLS or public-client membership. Use that
   login for `DATABASE_URL`. Audit logs are insert/read only for the runtime role.
4. Configure `.env.example` values for production: `APP_ENV=production`, explicit
   HTTPS frontend origins, a random signing secret and PostgreSQL
   `sslmode=verify-full` with a trusted CA (`sslrootcert` where necessary). Enforce
   HTTPS, trusted proxy addresses, aggregate auth rate limits and connection/body
   timeouts at the deployment proxy; the in-process IP limiter is per worker.
5. Deploy the updated API and frontend private-file flow together. Clear old
   tokens; log in again after password change/reset. Super Admin receipt scans
   need an explicit organization. Do not expose any server keys in the client.
6. Review historical bare file references with the existing Super Admin backfill
   tool before metadata edits. Compare historical stock against its movement
   ledger and physical stock; the old double-counting behavior may have affected
   balances. Do not invent corrections or silently rewrite historical evidence.
7. Re-run Supabase security advisors. Test public-client denial, dedicated-login
   operations, cross-organization denial, private file expiry, approvals and
   single inventory increments on staging and after deployment. Disable the
   unused Data API in the dashboard. Review backups, DB network restrictions,
   credential rotation and access logs separately; these settings were not read.

The server role policy permits the trusted FastAPI backend to access all app
rows. End-user role/organization authorization remains in FastAPI; these policies
do not implement Supabase Auth. Future tables need explicit server grants/RLS.

## Dependency checks

Patched and pinned FastAPI/Starlette, python-jose, python-multipart and
python-dotenv. Runtime imports now include email-validator/httpx explicitly;
test dependencies are in `requirements-dev.txt`.

Upstream fixes: [python-jose](https://github.com/mpdavis/python-jose/releases/tag/3.4.0),
[multipart](https://github.com/Kludex/python-multipart/security/advisories/GHSA-v9pg-7xvm-68hf),
[dotenv](https://github.com/theskumar/python-dotenv/security/advisories/GHSA-mf9w-mj56-hr94).
The environment audit also reports unpatched
[ECDSA timing behavior](https://github.com/tlsfuzzer/python-ecdsa/security/advisories/GHSA-wj6h-64fc-37mp)
in python-jose's transitive `ecdsa` package. This application restricts JWTs to
HS256 and does not perform ECDSA signing/key generation/ECDH. Keep this finding
visible and reassess before allowing EC algorithms; an audit with zero findings
is not claimed.

Final checks: **308 tests passed** (four dependency deprecation warnings), Python
compilation passed, `pip check` passed, and `git diff --check` passed. The repeated
dependency audit reports only the single ECDSA advisory described above (duplicate
entries from the advisory service). The SQL deployment script was statically
reviewed against live catalogs; it has not been executed on staging or production.

Verification commands:

```powershell
.\.venv\Scripts\python.exe -m pytest -q -p no:cacheprovider app
.\.venv\Scripts\python.exe -m pip check
```

The live hardening script remains unapplied; production protection is pending
the coordinated rollout above.
