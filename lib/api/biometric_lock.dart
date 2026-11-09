import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fingerprint or face, in front of a session that is already stored.
///
/// This holds no secret of its own. The renewal key in secure storage
/// is what actually signs you back in; all this decides is whether the
/// phone will hand it over without the device owner being present. So
/// a failed or refused check never destroys anything — it simply
/// leaves the session unopened and the password route available.
///
/// Off by default, and only offerable where the hardware is there and
/// enrolled. A switch that cannot work is worse than no switch.
class BiometricLock {
  BiometricLock({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  static const String _prefsKey = 'biometric_login_enabled';

  bool? _supported;

  /// Whether this device can do it at all, and has something enrolled.
  ///
  /// Cached: the answer cannot change while the app is open without the
  /// user going to system settings and coming back, and the call is a
  /// platform round trip that the settings screen would otherwise make
  /// on every rebuild.
  Future<bool> get isAvailable async {
    if (_supported case final known?) return known;
    try {
      final supported =
          await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
      // Supported hardware with nothing enrolled still cannot
      // authenticate anyone, so it does not count as available.
      final enrolled = supported
          ? (await _auth.getAvailableBiometrics()).isNotEmpty
          : false;
      return _supported = supported && enrolled;
    } catch (_) {
      // Anything at all means no: no hardware, no plugin registered
      // (a test host, a desktop build), or a platform that does not
      // answer. MissingPluginException is not a PlatformException, and
      // catching only the latter let it escape into restoreSession and
      // abandon the whole session restore — including the offline
      // viewer, which has nothing to do with fingerprints.
      return _supported = false;
    }
  }

  /// Whether the account has asked for it. False whenever the hardware
  /// is gone, so a phone that loses its enrolment does not lock anyone
  /// out of their own app.
  Future<bool> get isEnabled async {
    if (!await isAvailable) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Turning it on asks for the fingerprint first: a switch that
  /// enables something the owner cannot then pass would lock them out
  /// of their own session on the next launch.
  ///
  /// Returns what the setting ended up as, which is what the screen
  /// should show — not what was asked for.
  Future<bool> setEnabled(bool wanted) async {
    if (!wanted) {
      await _store(false);
      return false;
    }
    if (!await isAvailable) return false;
    if (!await prompt(reason: 'Confirm it is you before turning this on')) {
      return false;
    }
    await _store(true);
    return true;
  }

  Future<void> _store(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // A preference that cannot be written is not worth failing the
      // sign-in over; it simply reverts to off on the next launch.
    }
  }

  /// Shows the system prompt. True only on a real success.
  ///
  /// Every failure reads the same way — refused — because the
  /// difference between "no match", "cancelled" and "locked out" is
  /// the platform's business to explain in its own dialog, not ours to
  /// restate afterwards.
  Future<bool> prompt({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // The device PIN stays available: a wet or injured finger
          // must not mean the password route is the only way back.
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      // Same reasoning as isAvailable: a prompt that cannot be shown
      // is a refusal, not a crash on the launch path.
      return false;
    }
  }

  /// Forgets the preference. For signing out: the next account on this
  /// phone should not inherit the last one's unlock.
  Future<void> forget() => _store(false);
}
