import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/token_store.dart';
import 'package:smartevent/state/app_state.dart';

class _Token extends TokenStore {
  String? value = 'token';
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async => value = token;
  @override
  Future<void> clear() async => value = null;
}

/// A draft whose server record is gone can still be cleared.
///
/// Reported from a handset: "nag dedelete ako ng draft ayaw madelete".
/// The same screen's review history was answering "Event not found",
/// so the row the app was holding did not exist on the server. Delete
/// asked the server to remove something that was not there, the server
/// said 404, and the app reported that as a failure and kept the
/// draft — so every attempt failed the same way and the draft could
/// never be got rid of.
void main() {
  AppState appWith(MockClient client) => AppState(
    apiClient: ApiClient(tokenStore: _Token(), httpClient: client),
  );

  EventItem draft() => EventItem(
    remoteId: 'gone-from-the-server',
    title: 'Sample data',
    org: 'ACPES',
    date: '8 Jan 2027',
    budget: '₱0.00',
    status: EventApprovalStatus.draft,
  );

  test(
    'a 404 on delete clears it, because gone is what was asked for',
    () async {
      var calls = 0;
      final app = appWith(
        MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({'detail': 'Event not found'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(app.dispose);
      app.events.add(draft());

      final error = await app.deleteDraftEvent('gone-from-the-server');

      expect(calls, 1, reason: 'the server was not asked at all');
      expect(error, isNull, reason: 'the person was told it failed');
      expect(
        app.events.where((e) => e.remoteId == 'gone-from-the-server'),
        isEmpty,
        reason: 'the draft stayed in the list with no way to clear it',
      );
    },
  );

  test('any other refusal is still reported, and the draft stays', () async {
    // A 403 means somebody else owns it. Dropping it from the list
    // would hide a row that really is still there.
    final app = appWith(
      MockClient(
        (_) async => http.Response(
          jsonEncode({'detail': 'Not yours to delete'}),
          403,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(app.dispose);
    app.events.add(draft());

    final error = await app.deleteDraftEvent('gone-from-the-server');

    expect(error, isNotNull);
    expect(error, contains('Not yours to delete'));
    expect(
      app.events.where((e) => e.remoteId == 'gone-from-the-server'),
      isNotEmpty,
      reason: 'a draft that still exists was dropped from the list',
    );
  });

  test('a clean delete still works', () async {
    final app = appWith(MockClient((_) async => http.Response('', 204)));
    addTearDown(app.dispose);
    app.events.add(draft());

    expect(await app.deleteDraftEvent('gone-from-the-server'), isNull);
    expect(app.events, isEmpty);
  });
}
