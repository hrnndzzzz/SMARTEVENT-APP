import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the backend access token in the platform keychain/keystore rather
/// than in memory only, so closing the app doesn't force a fresh sign-in.
///
/// Every call is best-effort by design. A locked keychain, a wiped
/// keystore, a restricted web build or a user who cleared app data must
/// not take the app down — those cases degrade to "no stored token" and
/// the user signs in again. That is why nothing here rethrows.
///
/// Only the access token and the device's renewal key belong here.
/// Passwords and OTP codes are never persisted, and neither token is ever
/// written to logs or analytics.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _tokenKey = 'smartevent.access_token';

  /// The renewal key, swapped for a fresh access token without the
  /// password once the access token has expired — after a spell offline,
  /// say.
  static const String _renewalKey = 'smartevent.refresh_token';

  final FlutterSecureStorage _storage;

  Future<String?> read() => _read(_tokenKey);

  Future<String?> readRenewal() => _read(_renewalKey);

  Future<void> write(String token) => _write(_tokenKey, token);

  Future<void> writeRenewal(String token) => _write(_renewalKey, token);

  Future<String?> _read(String key) async {
    try {
      final token = await _storage.read(key: key);
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, String token) async {
    try {
      await _storage.write(key: key, value: token);
    } catch (_) {
      // Storage unavailable — the in-memory token still works for this
      // session, the user just signs in again next launch.
    }
  }

  /// The renewal key alone: the server ended it, or a sign-in came without
  /// one.
  Future<void> forgetRenewal() async {
    try {
      await _storage.delete(key: _renewalKey);
    } catch (_) {
      // The in-memory key is dropped by the caller either way.
    }
  }

  /// Both tokens: signing out keeps neither.
  Future<void> clear() async {
    for (final key in [_tokenKey, _renewalKey]) {
      try {
        await _storage.delete(key: key);
      } catch (_) {
        // Nothing recoverable to do; the in-memory tokens are cleared by
        // the caller either way, so this session is signed out regardless.
      }
    }
  }
}
