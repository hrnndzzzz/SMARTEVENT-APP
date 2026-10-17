import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/api/api_config.dart';
import 'package:smartevent/widgets/backend_address_card.dart';

Widget _host(http.Client client) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: BackendAddressCard(httpClient: client)),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiConfig.resetForTest();
  });

  testWidgets('a reachable address is saved and reported', (tester) async {
    var asked = Uri();
    final client = MockClient((request) async {
      asked = request.url;
      return http.Response('{"status":"ok"}', 200);
    });

    await tester.pumpWidget(_host(client));
    await tester.enterText(find.byType(TextField), '10.0.0.7:8001');
    await tester.tap(find.text('Save and test'));
    await tester.pumpAndSettle();

    // It probed the address that was typed, not the build's.
    expect(asked.toString(), 'http://10.0.0.7:8001/health');
    expect(ApiConfig.baseUrl, 'http://10.0.0.7:8001');
    expect(find.text('The backend answered.'), findsOneWidget);
  });

  testWidgets('a refused connection says so without claiming success', (
    tester,
  ) async {
    final client = MockClient((_) async => throw const SocketishFailure());

    await tester.pumpWidget(_host(client));
    await tester.enterText(find.byType(TextField), '10.0.0.8:8001');
    await tester.tap(find.text('Save and test'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not connect'), findsOneWidget);
    expect(find.text('The backend answered.'), findsNothing);
  });

  testWidgets('a timeout is distinguished from a refusal', (tester) async {
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(seconds: 20));
      return http.Response('', 200);
    });

    await tester.pumpWidget(_host(client));
    await tester.enterText(find.byType(TextField), '10.0.0.9:8001');
    await tester.tap(find.text('Save and test'));
    // Past the card's own 8s limit.
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();

    expect(find.textContaining('within 8 seconds'), findsOneWidget);

    // Let the mock's own delay elapse; an unfired timer outliving the
    // test is an error in its own right.
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('a non-200 answer still counts as reachable', (tester) async {
    // A backend without /health is still the right address, and saying
    // "could not connect" there would send someone hunting the network.
    final client = MockClient((_) async => http.Response('nope', 404));

    await tester.pumpWidget(_host(client));
    await tester.enterText(find.byType(TextField), '10.0.0.10:8001');
    await tester.tap(find.text('Save and test'));
    await tester.pumpAndSettle();

    expect(find.textContaining('404'), findsOneWidget);
    expect(find.textContaining('reachable'), findsOneWidget);
  });

  testWidgets('nonsense is refused before anything is probed', (tester) async {
    var probed = false;
    final client = MockClient((_) async {
      probed = true;
      return http.Response('', 200);
    });

    await tester.pumpWidget(_host(client));
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save and test'));
    await tester.pumpAndSettle();

    expect(probed, isFalse);
    expect(find.text('Enter an address.'), findsOneWidget);
  });
}

/// Stands in for the various socket errors a wrong address produces,
/// which differ by platform and are all handled the same way.
class SocketishFailure implements Exception {
  const SocketishFailure();
}
