import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';

import 'off_campus_test.dart' show host;

/// A proposal opened while the app could not reach the server holds no
/// version. Saving it anyway sent `expected_version: 0`, which the server
/// refuses, and would have sent blanks over whatever it does hold.
void main() {
  const json = {'content-type': 'application/json'};

  /// The first read of the proposal fails, as it does offline; later
  /// ones succeed.
  (SapService, List<http.Request>) serverDownOnce() {
    final sent = <http.Request>[];
    var reads = 0;
    final client = MockClient((request) async {
      sent.add(request);
      if (request.url.path.endsWith('/attachments')) {
        return http.Response('[]', 200, headers: json);
      }
      if (request.method == 'GET' && reads++ == 0) {
        return http.Response(
          '{"detail":"The database is temporarily unavailable"}',
          503,
          headers: json,
        );
      }
      return http.Response(
        jsonEncode({'id': 'p1', 'event_id': 'e1', 'state': 'draft', 'version': 2}),
        200,
        headers: json,
      );
    });
    return (SapService(ApiClient(httpClient: client)), sent);
  }

  test('a form that never loaded is not editable and sends nothing', () async {
    final (service, sent) = serverDownOnce();
    final form = SapForm(eventId: 'e1', service: service);

    await form.load();

    expect(form.proposal, isNull);
    expect(form.canEditProposerParts, isFalse);
    expect(await form.saveDetails(), isFalse);
    expect(sent.where((r) => r.method == 'PATCH'), isEmpty);
  });

  testWidgets('opening a part loads it again first', (tester) async {
    final (service, _) = serverDownOnce();
    final form = SapForm(eventId: 'e1', service: service);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: host(SapFormScreen(form: form)),
      ),
    );
    await tester.pumpAndSettle();
    expect(form.proposal, isNull);

    await tester.tap(find.text('Activity Details').first);
    await tester.pumpAndSettle();

    expect(find.byType(SapPart1Screen), findsOneWidget);
    expect(form.version, 2);
    expect(form.canEditProposerParts, isTrue);
  });
}
