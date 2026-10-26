import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/offline/offline_store.dart';
import 'package:smartevent/offline/offline_sync.dart';

void main() {
  test(
    'prepares never-opened details and all notification pages with bounded concurrency',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('offline-sync-');
      final store = await OfflineStore.open(
        directory: dir.path,
        factory: databaseFactoryFfi,
      );
      await store.activate('http://127.0.0.1:8000', {
        'id': 'a',
        'role': 'treasurer',
      });
      addTearDown(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
      var active = 0;
      var peak = 0;
      final paths = <String>[];
      final urls = <Uri>[];
      await store.put(
        OfflineStore.key('/reports/financial', {
          'period': 'yearly',
          'reference_date': '2025-01-01',
        }),
        {},
      );
      final api = ApiClient(
        offlineStore: store,
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active--;
          final path = request.url.path;
          paths.add(path);
          urls.add(request.url);
          if (path.endsWith('/export') || path.endsWith('/pdf')) {
            return http.Response(
              '%PDF-test',
              200,
              headers: {'content-type': 'application/pdf'},
            );
          }
          Object data = [];
          if (path == '/events')
            data = [
              {'id': 'unopened'},
            ];
          if (path == '/events/unopened') data = {'id': 'unopened'};
          if (path == '/notifications') {
            final offset = int.parse(request.url.queryParameters['offset']!);
            data = List.generate(
              offset == 0 ? 100 : 3,
              (i) => {'id': '${offset + i}'},
            );
          }
          return http.Response(jsonEncode(data), 200);
        }),
      );
      final sync = OfflineSync(api);
      await sync.prepare();
      expect((await store.read('/events/unopened'))?.data, {'id': 'unopened'});
      expect((await store.read('/notifications'))?.data, hasLength(103));
      expect(paths, contains('/events/unopened/sap-proposal'));
      expect(
        urls.any(
          (uri) =>
              uri.path == '/reports/financial/export' &&
              uri.queryParameters['reference_date'] == '2025-01-01',
        ),
        isTrue,
      );
      expect(peak, lessThanOrEqualTo(3));
      expect(sync.running, isFalse);
      sync.dispose();
    },
  );

  test(
    'foreground resume queues preparation while canceled requests drain',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('offline-resume-');
      final store = await OfflineStore.open(
        directory: dir.path,
        factory: databaseFactoryFfi,
      );
      await store.activate('http://127.0.0.1:8000', {
        'id': 'a',
        'role': 'sds_staff',
      });
      addTearDown(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
      final requested = Completer<void>();
      final response = Completer<http.Response>();
      final api = ApiClient(
        offlineStore: store,
        httpClient: MockClient((_) {
          if (!requested.isCompleted) requested.complete();
          return response.future;
        }),
      );
      final sync = OfflineSync(api);
      final first = sync.prepare();
      await requested.future;
      sync.foreground = false;
      sync.cancel();
      sync.foreground = true;
      await sync.prepare();
      response.complete(http.Response('[]', 200));
      await first;
      expect(sync.ready, isTrue);
      sync.dispose();
    },
  );
}
