import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/offline/offline_store.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/state/sap_form.dart';

void main() {
  late OfflineStore store;
  late Directory dir;
  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('offline-api-');
    store = await OfflineStore.open(
      directory: dir.path,
      factory: databaseFactoryFfi,
    );
    await store.activate('http://127.0.0.1:8000', {
      'id': 'a',
      'role': 'treasurer',
    });
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test(
    'successful reads persist and offline reads do not touch the network',
    () async {
      var requests = 0;
      final api = ApiClient(
        offlineStore: store,
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('[{"id":"one"}]', 200);
        }),
      );
      await api.get('/events');
      api.readOnly = true;
      expect(await api.get('/events'), [
        {'id': 'one'},
      ]);
      expect(requests, 1);
      expect(api.readStamps['/events']?.fromCache, isTrue);
    },
  );

  test(
    'server outage preserves saved records and enters read-only mode',
    () async {
      await store.put('/events', [
        {'id': 'saved'},
      ]);
      final api = ApiClient(
        offlineStore: store,
        httpClient: MockClient((_) async {
          throw http.ClientException('offline');
        }),
      );
      expect(await api.get('/events'), [
        {'id': 'saved'},
      ]);
      expect(api.readOnly, isTrue);
    },
  );

  test(
    'offline changes are rejected before the HTTP client is invoked',
    () async {
      var requests = 0;
      final api = ApiClient(
        offlineStore: store,
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      )..readOnly = true;
      for (final call in <Future<dynamic> Function()>[
        () => api.post('/events', body: {}),
        () => api.patch('/expenses/1', body: {}),
        () => api.put('/events/1/sap', body: {}),
        () => api.delete('/inventory/1'),
        () => api.upload(
          '/receipts',
          field: 'file',
          bytes: [1],
          filename: 'r.png',
          contentType: 'image/png',
        ),
      ]) {
        await expectLater(
          Future.sync(call),
          throwsA(isA<OfflineUnavailable>()),
        );
      }
      expect(requests, 0);
    },
  );

  test('a 403 removes the denied snapshot instead of serving it', () async {
    await store.put('/events/one', {'id': 'one'});
    final api = ApiClient(
      offlineStore: store,
      httpClient: MockClient(
        (_) async => http.Response('{"detail":"Forbidden"}', 403),
      ),
    );
    await expectLater(api.get('/events/one'), throwsA(isA<ApiException>()));
    expect(await store.read('/events/one'), isNull);
  });

  test('missing offline data is unavailable, never an empty success', () async {
    final api = ApiClient(offlineStore: store)..readOnly = true;
    await expectLater(api.get('/events'), throwsA(isA<OfflineUnavailable>()));
  });

  test(
    'logout rejects a late response before it can repopulate the cache',
    () async {
      final response = Completer<http.Response>();
      final api = ApiClient(
        offlineStore: store,
        httpClient: MockClient((_) => response.future),
      );
      final pending = api.get('/events');
      final assertion = expectLater(pending, throwsA(isA<SessionChanged>()));
      api.invalidateSession();
      await store.clear();
      await store.activate(api.baseUrl, {'id': 'b', 'role': 'treasurer'});
      response.complete(http.Response('[{"id":"old-account"}]', 200));
      await assertion;
      expect(await store.read('/events'), isNull);
    },
  );

  test(
    'private downloads keep bytes without retaining signed links or sending the API token',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        offlineStore: store,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/files') {
            return http.Response(
              '{"url":"https://storage.example/receipt?token=secret"}',
              200,
            );
          }
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      await api.storedFile('stable-reference');
      api.readOnly = true;
      expect((await api.storedFile('stable-reference')).bytes, [1, 2, 3]);
      expect(requests, hasLength(2));
      expect(
        (await store.keys()).any((key) => key.contains('secret')),
        isFalse,
      );
      expect(await store.read('/files?reference=stable-reference'), isNull);
    },
  );

  test(
    'offline SAP does not create a missing draft or allow local edits',
    () async {
      var requests = 0;
      final api = ApiClient(
        offlineStore: store,
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('{}', 404);
        }),
      )..readOnly = true;
      final form = SapForm(service: SapService(api), eventId: 'missing');
      await form.load();
      expect(form.canEditProposerParts, isFalse);
      expect(form.error, isNotNull);
      expect(await form.saveDetails(), isFalse);
      expect(requests, 0);
      form.dispose();
    },
  );

  test('explicit file access denial evicts previously saved bytes', () async {
    await store.putFile(
      'asset:receipt',
      [1],
      'image/png',
      'r.png',
      owner: '/receipts/r',
    );
    final api = ApiClient(
      offlineStore: store,
      httpClient: MockClient((_) async => http.Response('{}', 403)),
    );
    await expectLater(
      api.storedFile('receipt', policy: ReadPolicy.networkOnly),
      throwsA(isA<ApiException>()),
    );
    expect(await store.readFile('asset:receipt'), isNull);
  });
}
