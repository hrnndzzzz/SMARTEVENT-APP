import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smartevent/offline/offline_store.dart';

void main() {
  late Directory directory;
  late OfflineStore store;
  final profile = <String, dynamic>{
    'id': 'alice',
    'role': 'treasurer',
    'department_id': 'd1',
    'organization_id': 'o1',
    'is_active': true,
  };

  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('offline-test-');
    store = await OfflineStore.open(
      directory: directory.path,
      factory: databaseFactoryFfi,
    );
    await store.activate('https://api.example', profile);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('saved profile, records and file bytes survive reopening', () async {
    await store.put('/events', [
      {'id': 'event1'},
    ]);
    await store.putFile('receipt:1', [1, 2, 3], 'image/png', 'receipt.png');
    await store.close();
    store = await OfflineStore.open(
      directory: directory.path,
      factory: databaseFactoryFfi,
    );
    expect(store.session?.profile['id'], 'alice');
    expect((await store.read('/events'))?.data, [
      {'id': 'event1'},
    ]);
    expect((await store.readFile('receipt:1'))?.bytes, [1, 2, 3]);
  });

  test('removing a record removes its list entry and private files', () async {
    await store.put('/events', [
      {'id': 'a'},
      {'id': 'b'},
    ]);
    await store.putFile(
      'asset:a',
      [1],
      'image/png',
      'a.png',
      owner: '/events/a',
    );
    await store.remove('/events/a');
    expect((await store.read('/events'))?.data, [
      {'id': 'b'},
    ]);
    expect(await store.readFile('asset:a'), isNull);
    expect(await Directory('${directory.path}/files').list().length, 0);
  });

  test('income filters use the plural API route', () async {
    await store.put('/incomes', [
      {'id': 'a', 'event_id': 'e'},
      {'id': 'b', 'event_id': 'f'},
    ]);
    expect((await store.readRequest('/incomes', {'event_id': 'e'}))?.data, [
      {'id': 'a', 'event_id': 'e'},
    ]);
  });

  test('empty collection is distinct from one never downloaded', () async {
    await store.put('/events', []);
    expect((await store.read('/events'))?.data, isEmpty);
    expect(await store.read('/expenses'), isNull);
  });

  test('account or verified scope change clears records and files', () async {
    await store.put('/events', [
      {'id': 'private'},
    ]);
    await store.putFile('receipt:1', [1], 'image/png', 'receipt.png');
    await store.activate('https://api.example', {
      ...profile,
      'organization_id': 'o2',
    });
    expect(await store.read('/events'), isNull);
    expect(await store.readFile('receipt:1'), isNull);
    await store.put('/events', [
      {'id': 'other'},
    ]);
    await store.activate('https://api.example', {...profile, 'id': 'bob'});
    expect(await store.read('/events'), isNull);
  });

  test('replacing a saved file removes the previous bytes', () async {
    await store.putFile('asset', [1], 'image/png', 'a.png');
    await store.putFile('asset', [2], 'image/png', 'a.png');
    expect((await store.readFile('asset'))?.bytes, [2]);
    expect(await Directory('${directory.path}/files').list().length, 1);
  });

  test('logout rejects responses belonging to the old session', () async {
    final generation = store.generation;
    await store.clear();
    await store.put('/events', [
      {'id': 'late'},
    ], generation: generation);
    await store.activate('https://api.example', profile);
    expect(await store.read('/events'), isNull);
  });

  test('request keys normalize query order without merging report dates', () {
    expect(
      OfflineStore.key('/reports/financial', {
        'period': 'monthly',
        'reference_date': '2026-10-01',
      }),
      OfflineStore.key('/reports/financial', {
        'reference_date': '2026-10-01',
        'period': 'monthly',
      }),
    );
    expect(
      OfflineStore.key('/reports/financial', {'reference_date': '2026-11-01'}),
      isNot(
        OfflineStore.key('/reports/financial', {
          'reference_date': '2026-10-01',
        }),
      ),
    );
  });

  test(
    'filters use downloaded collections including movement-linked inventory',
    () async {
      await store.put('/events', [
        {'id': 'a', 'school_year': '2026-2027'},
        {'id': 'b', 'school_year': null},
      ]);
      expect(
        (await store.readRequest('/events', {
          'school_year': '2026-2027',
        }))?.data,
        [
          {'id': 'a', 'school_year': '2026-2027'},
        ],
      );
      await store.put('/inventory', [
        {'id': 'i1', 'event_id': 'a', 'is_draft': false},
        {'id': 'i2', 'event_id': 'a', 'is_draft': false},
      ]);
      await store.put('/inventory/i1/transactions', [
        {'event_id': 'b'},
      ]);
      await store.put('/inventory/i2/transactions', []);
      expect((await store.readRequest('/inventory', {'event_id': 'b'}))?.data, [
        {'id': 'i1', 'event_id': 'a', 'is_draft': false},
      ]);
    },
  );
}
