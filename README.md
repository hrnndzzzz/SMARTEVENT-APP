# SMARTEVENT backend workspace

The Python backend source, requirements, scripts, and API documentation are in
[smartevent-backend/](smartevent-backend/README.md). That source folder was preserved
in its existing location during the frontend cleanup on 2026-10-09.

This directory also retains the local Python environment, private configuration,
Supabase metadata, and backend diagnostic tools. The empty `app/static/` directory
is a leftover directory, not the Python application entrypoint.

Duplicate Flutter and platform files were moved to
`../_backend_frontend_recovery_20261009/` for recovery. The Flutter SDK used by the
outer mobile project was relocated to `../.tools/flutter-sdk/`.

The more recent backend implementation previously discussed in this chat is
missing from the current checkout. This cleanup preserves the available source;
it does not restore those missing changes or certify this checkout as current.
