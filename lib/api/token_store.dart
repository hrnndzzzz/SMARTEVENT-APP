import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the backend access token in the platform keychain/keystore rather
/// than in memory only, so closing the app doesn't force a fresh sign-in.
///
/// Every call is best-effort by design. A locked keychain, a wiped
/// keystore, a restricted web build or a user who cleared app data must
/// not take the app down — those cases degrade to "no stored token" and
/// the user signs in again. That is why nothing here rethrows.
///
/// Only the access token belongs here. Passwords and OTP codes are never
/// persisted, and the token is never written to logs or analytics.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _tokenKey = 'smartevent.access_token';

  final FlutterSecureStorage _storage;

  Future<String?> read() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {
      // Storage unavailable — the in-memory token still works for this
      // session, the user just signs in again next launch.
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      // Nothing recoverable to do; the in-memory token is cleared by the
      // caller either way, so this session is signed out regardless.
    }
  }
}
