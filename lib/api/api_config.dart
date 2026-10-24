import 'package:shared_preferences/shared_preferences.dart';

/// Where the app looks for the SMARTEVENT backend.
///
/// The app talks to the FastAPI backend and to nothing else. It never
/// reaches Supabase directly: database URLs, the service-role key, Resend
/// keys, Gemini keys and the JWT signing secret live in the backend's own
/// `.env` and must never ship inside a client build.
/// See `smartevent-backend/FRONTEND_README.md` §1.
///
/// The address is settable on the device as well as at build time. A
/// build-time define is right for a deployed build, but during development
/// the backend moves — a laptop's LAN address changes with the network, a
/// hotspot hands out a different subnet, a cable gets swapped for
/// `adb reverse`. When the address could only be set at compile time, each
/// of those meant a full rebuild and a reinstall before the app could reach
/// anything. Now it means typing a new address into Settings.
class ApiConfig {
  const ApiConfig._();

  static const String _prefsKey = 'api_base_url_override';

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
  ///
  /// Deliberately loopback rather than anyone's LAN address. A committed
  /// IP works on one laptop on one network and silently hangs for
  /// everyone else, which is what it did.
  static const String _localDevFallback = 'http://127.0.0.1:8000';

  /// Set on this device, and preferred over the build-time value when it
  /// is. Null means "use whatever the build was pointed at".
  static String? _override;
  static Future<void> Function()? beforeServerChange;

  /// Whether a base URL was supplied at build time. False means the build
  /// is pointing at the local development fallback, which is never right
  /// for a release.
  static bool get isConfigured => _configured.isNotEmpty;

  /// What the build alone would use, ignoring anything set on the device.
  /// This is what [clearOverride] goes back to.
  static String get defaultBaseUrl =>
      normalise(isConfigured ? _configured : _localDevFallback);

  /// Whether this device is pointing somewhere other than the build's own
  /// address, which Settings says out loud so a puzzling "cannot reach the
  /// backend" is traceable to an address someone typed weeks ago.
  static bool get hasOverride => _override != null;

  static String get baseUrl => _override ?? defaultBaseUrl;

  /// Reads the stored address. Called once before `runApp`; a failure here
  /// is not worth blocking startup for, since the build-time address is
  /// still perfectly usable.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      _override = (stored == null || stored.isEmpty) ? null : stored;
    } catch (_) {
      _override = null;
    }
  }

  /// Points this device at [value] and remembers it. Throws
  /// [FormatException] if the address could not be made sense of, so the
  /// caller can say why rather than silently storing something unusable.
  static Future<void> setOverride(String value) async {
    final cleaned = normalise(value);
    if (cleaned.isEmpty) {
      throw const FormatException('Enter an address.');
    }
    final uri = Uri.tryParse(cleaned);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException(
        'That is not an address the app can reach. '
        'It should look like 192.168.1.5:8000.',
      );
    }
    if (cleaned != baseUrl) await beforeServerChange?.call();
    _override = cleaned;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, cleaned);
    } catch (_) {
      // The address still applies for this run even if it could not be
      // written down, which is better than refusing the change outright.
    }
  }

  /// Goes back to the address the build was made with.
  static Future<void> clearOverride() async {
    if (baseUrl != defaultBaseUrl) await beforeServerChange?.call();
    _override = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {
      // Same reasoning as setOverride.
    }
  }

  /// Tidies what someone typed into something [Uri.parse] can use.
  ///
  /// A bare `192.168.1.5:8000` is what anyone reads off a terminal, so it
  /// gets `http://` rather than a complaint — https is never right for the
  /// development backends this field exists for, and a typed scheme is
  /// always kept.
  static String normalise(String value) {
    var cleaned = value.trim();
    if (cleaned.isEmpty) return '';
    if (!cleaned.contains('://')) {
      cleaned = 'http://$cleaned';
    }
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned;
  }

  /// Only for tests, which must not leak an address into each other.
  static void resetForTest() => _override = null;
}
