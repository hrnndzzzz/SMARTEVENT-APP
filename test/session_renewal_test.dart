import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/auth_service.dart';
import 'package:smartevent/api/token_store.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// Both tokens, in memory.
class MemoryTokens extends TokenStore {
  MemoryTokens({this.token, this.renewal});
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
  Future<void> clear() async => token = renewal = null;
}

/// An hour's login token runs out, offline or not. Coming back used to mean
/// the sign-in box; the device's renewal key now brings a fresh one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = {
    'id': 'a',
    'full_name': 'Alice',
    'email': 'alice@example.test',
    'role': 'treasurer',
    'is_active': true,
    'created_at': '2026-01-01T00:00:00Z',
  };

  late List<String> asked;

  /// A server whose good token is "fresh"; anything else is expired.
  /// [renewWith] is what `/auth/refresh` answers.
  ApiClient serverWith(
    MemoryTokens tokens, {
    int renewWith = 200,
  }) {
    asked = [];
    return ApiClient(
      tokenStore: tokens,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        asked.add(path);
        if (path == '/auth/refresh') {
          final key = (jsonDecode(request.body) as Map)['refresh_token'];
          return renewWith == 200 && key == 'renewal-key'
              ? http.Response(
                  jsonEncode({
                    'access_token': 'fresh',
                    'refresh_token': 'renewal-key',
                  }),
                  200,
                )
              : http.Response('{"detail":"Sign in again"}', 401);
        }
        if (path == '/auth/logout') return http.Response('', 204);
        if (request.headers['Authorization'] != 'Bearer fresh') {
          return http.Response('{"detail":"Could not validate"}', 401);
        }
        if (path == '/auth/me') return http.Response(jsonEncode(profile), 200);
        if (path == '/auth/permissions') return http.Response('{}', 404);
        return http.Response('[]', 200);
      }),
    );
  }

  test('an expired token is renewed and the request sent again', () async {
    final tokens = MemoryTokens(token: 'expired', renewal: 'renewal-key');
    final api = serverWith(tokens);
    await api.restoreToken();

    final me = await api.get('/auth/me');

    expect((me as Map)['id'], 'a');
    expect(asked, ['/auth/me', '/auth/refresh', '/auth/me']);
    expect(tokens.token, 'fresh', reason: 'kept for the next launch');
    expect(api.requiresSignIn, isFalse);
  });

  test('requests that meet the expiry together renew once', () async {
    final tokens = MemoryTokens(token: 'expired', renewal: 'renewal-key');
    final api = serverWith(tokens);
    await api.restoreToken();

    await Future.wait([api.get('/events'), api.get('/expenses')]);

    expect(asked.where((p) => p == '/auth/refresh'), hasLength(1));
  });

  test('a key the server has ended leaves only signing in', () async {
    final tokens = MemoryTokens(token: 'expired', renewal: 'renewal-key');
    final api = serverWith(tokens, renewWith: 401);
    await api.restoreToken();

    await expectLater(api.get('/auth/me'), throwsA(isA<ApiException>()));

    expect(api.requiresSignIn, isTrue);
    expect(api.canRenew, isFalse);
    expect(tokens.renewal, isNull, reason: 'not offered again');
  });

  test('a wrong password is not mistaken for an expired token', () async {
    final tokens = MemoryTokens(token: 'expired', renewal: 'renewal-key');
    final api = serverWith(tokens);
    await api.restoreToken();

    await expectLater(
      AuthService(api).login(email: 'alice@example.test', password: 'nope'),
      throwsA(isA<ApiException>()),
    );

    expect(asked, isNot(contains('/auth/refresh')));
  });

  test('signing out ends the key on the server and on the phone', () async {
    final tokens = MemoryTokens(token: 'fresh', renewal: 'renewal-key');
    final api = serverWith(tokens);
    await api.restoreToken();

    await AuthService(api).logout();
    await pumpEventQueue();

    expect(asked, contains('/auth/logout'));
    expect(tokens.token, isNull);
    expect(tokens.renewal, isNull);
  });

  testWidgets('pulling a screen down asks the server again', (tester) async {
    var pulled = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: BrutScreen(
          onRefresh: () async => pulled++,
          child: const Text('a short screen'),
        ),
      ),
    );

    await tester.fling(find.text('a short screen'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(pulled, 1, reason: 'even when there is nothing to scroll');
  });

  test('opening the app after hours away renews, with no sign-in', () async {
    final tokens = MemoryTokens(token: 'expired', renewal: 'renewal-key');
    final app = AppState(apiClient: serverWith(tokens));

    await app.restoreSession();

    expect(app.currentAccount?.id, 'a');
    expect(app.requiresOnlineSignIn, isFalse);
    expect(app.isOfflineViewing, isFalse);
    app.dispose();
  });
}
