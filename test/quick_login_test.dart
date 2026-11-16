import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_auth/local_auth.dart';
// AuthMessages is not re-exported by local_auth itself; an override has
// to name the same type the real signature uses.
import 'package:local_auth_platform_interface/types/auth_messages.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/auth_service.dart';
import 'package:smartevent/api/biometric_lock.dart';
import 'package:smartevent/api/token_store.dart';
import 'package:smartevent/screens/settings_screen.dart';
import 'package:smartevent/screens/signin_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/sfx.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Getting back in with a fingerprint instead of a password.
///
/// Biometrics were already here, but only as a gate that fired by
/// itself at launch and was switched on four sections down in Settings.
/// So two things were missing: a way to *ask* for the lock — handing
/// the phone over used to mean either leaving the session open or
/// signing out and typing an email address and ten characters to come
/// back — and the offer made where it is obviously worth something,
/// which is right after a password has been typed.
///
/// The decision underneath all of it: locking is not signing out.
/// Nothing in here keeps a credential past a sign-out, so a signed-out
/// phone still holds nothing that can open the account.
class _FakeAuth implements LocalAuthentication {
  _FakeAuth({this.enrolled = const [BiometricType.fingerprint]});

  final List<BiometricType> enrolled;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => enrolled;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const <AuthMessages>[],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async => true;

  @override
  Future<bool> stopAuthentication() async => true;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The keystore, in memory, so a test can see what was left behind on
/// the phone rather than taking a method's word for it.
class _FakeStore implements TokenStore {
  String? token;
  String? renewal;

  @override
  Future<String?> read() async => token;

  @override
  Future<String?> readRenewal() async => renewal;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> writeRenewal(String value) async => renewal = value;

  @override
  Future<void> forgetRenewal() async => renewal = null;

  @override
  Future<void> clear() async {
    token = null;
    renewal = null;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A server that grants a session to anything.
  ApiClient signingIn(_FakeStore store) => ApiClient(
    tokenStore: store,
    httpClient: MockClient(
      (_) async => http.Response(
        '{"access_token":"an-access-token",'
        '"refresh_token":"a-renewal-key"}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  );

  group('keeping the session on this phone', () {
    // The box was decoration: `_rememberMe` was set by the checkbox and
    // read by nothing at all, and the session was kept either way. A
    // control that does nothing is the same fault as the dead Send for
    // review button, and in a worse place — it is a promise about where
    // a credential goes.
    test('a remembered sign-in leaves both tokens on the phone', () async {
      final store = _FakeStore();
      await AuthService(
        signingIn(store),
      ).login(email: 'a@lcup.edu.ph', password: 'x');

      expect(store.token, 'an-access-token');
      expect(store.renewal, 'a-renewal-key');
    });

    test('an unremembered one leaves nothing', () async {
      final store = _FakeStore();
      final client = signingIn(store);
      await AuthService(
        client,
      ).login(email: 'a@lcup.edu.ph', password: 'x', remember: false);

      expect(store.token, isNull);
      expect(store.renewal, isNull);
      expect(
        client.hasToken,
        isTrue,
        reason: 'the session still works; it is only held in memory',
      );
    });

    test('and it clears what an earlier remembered sign-in left', () async {
      final store = _FakeStore()
        ..token = 'yesterdays-token'
        ..renewal = 'yesterdays-key';

      await AuthService(
        signingIn(store),
      ).login(email: 'a@lcup.edu.ph', password: 'x', remember: false);

      expect(
        store.token,
        isNull,
        reason:
            'a stale token left in the keystore would be restored on '
            'the next launch, signing in somebody who asked not to be',
      );
      expect(store.renewal, isNull);
    });

    test('a renewal does not write a session that is not kept', () async {
      // The token lasts an hour. Without this the thing the user asked
      // not to keep would write itself to the keystore sixty minutes
      // later, from inside a request nobody was watching.
      final store = _FakeStore();
      final client = signingIn(store);
      await client.setToken('t', renewal: 'r', persist: false);

      expect(await client.renewSession(), isTrue);
      expect(store.token, isNull);
    });

    test('a session read off the phone is one the phone may keep', () async {
      final store = _FakeStore()..token = 'stored';
      final client = ApiClient(tokenStore: store);
      await client.setToken('t', persist: false);

      await client.restoreToken();

      expect(client.persistSession, isTrue);
    });
  });

  group('locking instead of signing out', () {
    Future<AppState> signedIn({
      bool persist = true,
      bool biometrics = true,
      List<BiometricType> enrolled = const [BiometricType.fingerprint],
    }) async {
      final client = ApiClient(tokenStore: _FakeStore());
      final app = AppState(apiClient: client);
      final lock = BiometricLock(auth: _FakeAuth(enrolled: enrolled));
      if (biometrics) await lock.setEnabled(true);
      app.biometricLock = lock;
      await client.setToken('a-token', renewal: 'a-key', persist: persist);
      return app;
    }

    test('a kept session behind a fingerprint can be locked', () async {
      final app = await signedIn();

      expect(await app.lockNow(), isTrue);
      expect(app.isLocked, isTrue);
    });

    test('an unremembered session cannot', () async {
      // It would have nothing to reopen, so the lock would be a
      // sign-out wearing a nicer word.
      final app = await signedIn(persist: false);

      expect(await app.lockNow(), isFalse);
      expect(app.isLocked, isFalse);
    });

    test('nor one with the switch off', () async {
      final app = await signedIn(biometrics: false);

      expect(await app.lockNow(), isFalse);
    });

    test('nor the demo, which holds no session', () async {
      final app = await signedIn();
      app.enterDemo(role: UserRole.treasurer);

      expect(await app.lockNow(), isFalse);
    });

    test('nor a signed-out phone', () async {
      final client = ApiClient(tokenStore: _FakeStore());
      final app = AppState(apiClient: client);
      final lock = BiometricLock(auth: _FakeAuth());
      await lock.setEnabled(true);
      app.biometricLock = lock;

      expect(
        await app.lockNow(),
        isFalse,
        reason:
            'asking a signed-out phone for a fingerprint protects '
            'nothing and only stands in front of the sign-in screen',
      );
    });

    test('locking twice is still once', () async {
      final app = await signedIn();
      await app.lockNow();

      expect(await app.lockNow(), isFalse);
      expect(app.isLocked, isTrue);
    });
  });

  group('what the label is allowed to say', () {
    // A button reading "Unlock with fingerprint" on a face-only phone
    // is a small lie that costs a tap to discover.
    Future<String?> kindOf(List<BiometricType> enrolled) =>
        BiometricLock(auth: _FakeAuth(enrolled: enrolled)).kind;

    test('a fingerprint is a fingerprint', () async {
      expect(await kindOf(const [BiometricType.fingerprint]), 'fingerprint');
    });

    test('a face is a face', () async {
      expect(await kindOf(const [BiometricType.face]), 'face');
    });

    test('both is both', () async {
      expect(
        await kindOf(const [BiometricType.face, BiometricType.fingerprint]),
        'fingerprint or face',
      );
    });

    test(
      'and a platform that will not say gets no claim made for it',
      () async {
        // What Android actually reports: BiometricPrompt hides which
        // modality answered, so local_auth says `strong` or `weak`.
        expect(await kindOf(const [BiometricType.strong]), isNull);
      },
    );
  });

  group('the offer after a password', () {
    test('is made on a phone that could do it', () async {
      expect(await BiometricLock(auth: _FakeAuth()).shouldOffer, isTrue);
    });

    test('is not made once it is already on', () async {
      final lock = BiometricLock(auth: _FakeAuth());
      await lock.setEnabled(true);

      expect(await lock.shouldOffer, isFalse);
    });

    test('is not made twice', () async {
      final lock = BiometricLock(auth: _FakeAuth());
      await lock.declineOffer();

      expect(
        await lock.shouldOffer,
        isFalse,
        reason: 'an offer that comes back every time is not an offer',
      );
    });

    test('is not made where the hardware cannot do it', () async {
      final lock = BiometricLock(auth: _FakeAuth(enrolled: const []));

      expect(await lock.shouldOffer, isFalse);
    });
  });

  group('the screens', () {
    Widget signInScreen(AppState app) => ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(theme: AppTheme.light(), home: const SignInScreen()),
    );

    Widget settingsScreen(AppState app) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => SfxPlayer()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const SettingsScreen()),
    );

    testWidgets('unticking the box says what it costs', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = AppState();
      addTearDown(app.dispose);

      await tester.pumpWidget(signInScreen(app));
      await tester.pumpAndSettle();

      // Nothing while it is ticked: small print under a box that costs
      // nothing is noise.
      expect(find.textContaining('will not be kept'), findsNothing);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(find.textContaining('will not be kept'), findsOneWidget);
      expect(
        find.textContaining('fingerprint cannot bring it back'),
        findsOneWidget,
      );
    });

    testWidgets('Settings offers the lock only where it would work', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // A demo holds no session, so the row would be a dead control —
      // which is the fault this whole batch of work started with.
      final app = AppState()..enterDemo(role: UserRole.treasurer);
      addTearDown(app.dispose);
      app.biometricLock = BiometricLock(auth: _FakeAuth());
      await app.biometricLock.setEnabled(true);

      await tester.pumpWidget(settingsScreen(app));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Lock SmartEvent now'), findsNothing);
      expect(find.textContaining('The demo holds none'), findsOneWidget);
    });

    testWidgets('and offers it on a real kept session', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = ApiClient(tokenStore: _FakeStore());
      final app = AppState(apiClient: client);
      addTearDown(app.dispose);
      app.biometricLock = BiometricLock(auth: _FakeAuth());
      await app.biometricLock.setEnabled(true);
      await client.setToken('a-token', renewal: 'a-key');

      await tester.pumpWidget(settingsScreen(app));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Lock SmartEvent now'), findsOneWidget);
      // The one thing that has to be clear about it: this is not the
      // sign-out. MonoLabel uppercases what it is given, and clips it
      // to one line, which is why the row says it in three words.
      expect(find.text('STAYS SIGNED IN'), findsOneWidget);
    });
  });
}
