import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/token_store.dart';
import 'package:smartevent/offline/offline_store.dart';
import 'package:smartevent/state/app_state.dart';

class MemoryToken extends TokenStore {
  String? value = 'expired-token';
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    value = token;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late OfflineStore store;
  final profile = <String, dynamic>{
    'id': 'a',
    'full_name': 'Alice',
    'email': 'alice@example.test',
    'role': 'sds_staff',
    'is_active': true,
    'created_at': '2026-01-01T00:00:00Z',
  };
  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('offline-session-');
    store = await OfflineStore.open(
      directory: dir.path,
      factory: databaseFactoryFfi,
    );
    await store.activate('http://127.0.0.1:8000', profile);
    await store.put('/proposal-letters', []);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  for (final status in [401, 503]) {
    test('restores saved viewer after auth returns $status', () async {
      final api = ApiClient(
        offlineStore: store,
        tokenStore: MemoryToken(),
        httpClient: MockClient((_) async => http.Response('{}', status)),
      );
      final app = AppState(apiClient: api);
      await app.restoreSession();
      expect(app.currentAccount?.id, 'a');
      expect(app.isOfflineViewing, isTrue);
      expect(app.sessionChecked, isTrue);
      await app.signOut();
      expect(store.session, isNull);
      expect(await store.read('/proposal-letters'), isNull);
      app.dispose();
    });
  }
  test('loads saved data when the server cannot be reached at all', () async {
    final api = ApiClient(
      offlineStore: store,
      tokenStore: MemoryToken(),
      httpClient: MockClient((_) async => throw http.ClientException('down')),
    );
    final app = AppState(apiClient: api);
    // The permissions lookup fails too; it must not stop the modules loading.
    await app.restoreSession();
    expect(app.isOfflineViewing, isTrue);
    expect(app.lettersLoad.status, LoadStatus.ready);
    app.dispose();
  });

  test('explicit account denial removes saved viewer', () async {
    final api = ApiClient(
      offlineStore: store,
      tokenStore: MemoryToken(),
      httpClient: MockClient((_) async => http.Response('{}', 403)),
    );
    final app = AppState(apiClient: api);
    await app.restoreSession();
    expect(app.currentAccount, isNull);
    expect(store.session, isNull);
    app.dispose();
  });

  test(
    'scope revalidation rejects requests started with the previous scope',
    () async {
      final pending = Completer<http.Response>();
      final api = ApiClient(
        offlineStore: store,
        tokenStore: MemoryToken(),
        httpClient: MockClient((request) async {
          if (request.url.path == '/events') return pending.future;
          if (request.url.path == '/auth/permissions') {
            return http.Response('{}', 404);
          }
          if (request.url.path == '/auth/me') {
            return http.Response(
              jsonEncode({...profile, 'organization_id': 'new-scope'}),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      final app = AppState(apiClient: api)..devQuickLogin(UserRole.sdsStaff);
      final oldRead = api.get('/events');
      final assertion = expectLater(oldRead, throwsA(isA<SessionChanged>()));
      await app.retryOfflinePreparation();
      pending.complete(http.Response('[{"id":"old-scope"}]', 200));
      await assertion;
      expect(await store.read('/events'), isNull);
      app.dispose();
    },
  );

  test('password setup refusal revokes an older offline viewer', () async {
    final api = ApiClient(
      offlineStore: store,
      tokenStore: MemoryToken(),
      httpClient: MockClient(
        (_) async =>
            http.Response('{"detail":"Password change required"}', 403),
      ),
    );
    final app = AppState(apiClient: api);
    await app.restoreSession();
    expect(app.mustSetPassword, isTrue);
    expect(store.session, isNull);
    app.dispose();
  });

  test(
    'a denied refresh removes records already displayed in memory',
    () async {
      await store.put('/proposal-letters', [
        {
          'id': 'letter',
          'event_id': 'event',
          'title': 'Private letter',
          'document_url': 'private-reference',
          'submitted_by': 'a',
          'created_at': '2026-01-01T00:00:00Z',
        },
      ]);
      var deny = false;
      final api = ApiClient(
        offlineStore: store,
        tokenStore: MemoryToken(),
        httpClient: MockClient(
          (_) async => http.Response('{}', deny ? 403 : 503),
        ),
      );
      final app = AppState(apiClient: api);
      await app.restoreSession();
      expect(app.letters, hasLength(1));
      deny = true;
      api.readOnly = false;
      await app.loadLetters();
      expect(app.letters, isEmpty);
      expect(app.lettersLoad.hasFailed, isTrue);
      app.dispose();
    },
  );

  test(
    'saved viewer opens before an unreachable server request times out',
    () async {
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      final api = ApiClient(
        offlineStore: store,
        tokenStore: MemoryToken(),
        httpClient: MockClient((_) {
          requested.complete();
          return response.future;
        }),
      );
      final app = AppState(apiClient: api);
      final restoring = app.restoreSession();
      await requested.future;
      final visibleBeforeResponse =
          app.sessionChecked &&
          app.currentAccount?.id == 'a' &&
          app.isOfflineViewing;
      response.complete(http.Response('{}', 503));
      await restoring;
      expect(visibleBeforeResponse, isTrue);
      app.dispose();
    },
  );
}
