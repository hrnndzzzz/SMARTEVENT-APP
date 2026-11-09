import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
// AuthMessages is not re-exported by local_auth itself; the override
// below has to name the same type the real signature uses.
import 'package:local_auth_platform_interface/types/auth_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/api/biometric_lock.dart';

/// The gate in front of a stored session.
///
/// What matters is not that it prompts, but what it does when the
/// prompt is refused: nothing is destroyed, and the switch never ends
/// up on for a device that cannot pass it.
class _FakeAuth implements LocalAuthentication {
  _FakeAuth({
    this.supported = true,
    this.canCheck = true,
    this.enrolled = const [BiometricType.fingerprint],
    this.succeeds = true,
    this.throws = false,
  });

  final bool supported;
  final bool canCheck;
  final List<BiometricType> enrolled;
  bool succeeds;
  final bool throws;

  int prompts = 0;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => enrolled;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const <AuthMessages>[],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    prompts++;
    if (throws) throw PlatformException(code: 'NotAvailable');
    return succeeds;
  }

  @override
  Future<bool> stopAuthentication() async => true;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('availability', () {
    test('hardware with something enrolled is available', () async {
      expect(await BiometricLock(auth: _FakeAuth()).isAvailable, isTrue);
    });

    test('hardware with nothing enrolled is not', () async {
      final lock = BiometricLock(auth: _FakeAuth(enrolled: const []));

      expect(
        await lock.isAvailable,
        isFalse,
        reason: 'supported hardware cannot authenticate an empty enrolment',
      );
    });

    test('a platform that refuses the question is not', () async {
      final lock = BiometricLock(auth: _FakeAuth(throws: true, supported: false));

      expect(await lock.isAvailable, isFalse);
    });
  });

  group('turning it on', () {
    test('asks first, and stays on when confirmed', () async {
      final auth = _FakeAuth();
      final lock = BiometricLock(auth: auth);

      expect(await lock.setEnabled(true), isTrue);
      expect(auth.prompts, 1, reason: 'it must confirm before enabling');
      expect(await lock.isEnabled, isTrue);
    });

    test('stays off when the prompt is refused', () async {
      final lock = BiometricLock(auth: _FakeAuth(succeeds: false));

      expect(await lock.setEnabled(true), isFalse);
      expect(
        await lock.isEnabled,
        isFalse,
        reason: 'enabling a lock the owner cannot pass locks them out',
      );
    });

    test('cannot be turned on where it is unavailable', () async {
      final lock = BiometricLock(auth: _FakeAuth(enrolled: const []));

      expect(await lock.setEnabled(true), isFalse);
    });

    test('turning it off needs no prompt', () async {
      final auth = _FakeAuth();
      final lock = BiometricLock(auth: auth);
      await lock.setEnabled(true);
      final before = auth.prompts;

      expect(await lock.setEnabled(false), isFalse);
      expect(auth.prompts, before, reason: 'leaving is never gated');
      expect(await lock.isEnabled, isFalse);
    });
  });

  group('once on', () {
    test('it reports off again if the enrolment goes away', () async {
      SharedPreferences.setMockInitialValues({
        'biometric_login_enabled': true,
      });
      final lock = BiometricLock(auth: _FakeAuth(enrolled: const []));

      expect(
        await lock.isEnabled,
        isFalse,
        reason: 'a phone that loses its fingerprint must not lock its owner '
            'out of their own app',
      );
    });

    test('a refused unlock is false, not an exception', () async {
      final lock = BiometricLock(auth: _FakeAuth(succeeds: false));

      expect(await lock.prompt(reason: 'test'), isFalse);
    });

    test('a platform error is a refusal, not a crash', () async {
      final lock = BiometricLock(auth: _FakeAuth(throws: true));

      expect(await lock.prompt(reason: 'test'), isFalse);
    });

    test('forgetting leaves it off', () async {
      final lock = BiometricLock(auth: _FakeAuth());
      await lock.setEnabled(true);

      await lock.forget();

      expect(await lock.isEnabled, isFalse);
    });
  });
}
