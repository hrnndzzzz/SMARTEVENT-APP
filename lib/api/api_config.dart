/// Where the app looks for the SMARTEVENT backend.
///
/// The app talks to the FastAPI backend and to nothing else. It never
/// reaches Supabase directly: database URLs, the service-role key, Resend
/// keys, Gemini keys and the JWT signing secret live in the backend's own
/// `.env` and must never ship inside a client build.
/// See `smartevent-backend/FRONTEND_README.md` §1.
class ApiConfig {
  const ApiConfig._();

  /// Set at build time so one source tree can target local, staging and
  /// production without editing code:
  ///
  /// ```
  /// flutter run --dart-define=SMARTEVENT_API_BASE_URL=http://10.0.2.2:8000
  /// flutter build apk --dart-define=SMARTEVENT_API_BASE_URL=https://api.example.org
  /// ```
  static const String _configured = String.fromEnvironment(
    'SMARTEVENT_API_BASE_URL',
  );

  /// Used only when nothing was defined at build time. This reaches a
  /// backend on the developer's own machine, which means the emulator or
  /// device has to be able to resolve it: either run
  /// `adb reverse tcp:8000 tcp:8000`, or pass `http://10.0.2.2:8000`
  /// (Android emulator) or the machine's LAN IP via the define above.
  static const String _localDevFallback = 'http://127.0.0.1:8000';

  /// Whether a base URL was supplied at build time. False means the build
  /// is pointing at the local development fallback, which is never right
  /// for a release.
  static bool get isConfigured => _configured.isNotEmpty;

  static String get baseUrl {
    final value = isConfigured ? _configured : _localDevFallback;
    return value.endsWith('/')
        ? value.substring(0, value.length - 1)
        : value;
  }
}
