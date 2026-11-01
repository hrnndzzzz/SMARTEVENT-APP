import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// F12: a returned proposal is edited against the marks and resubmitted.
///
/// Editing and resubmitting already worked — revision_requested is a
/// proposer-editable state. What was missing is the marks: the server
/// has carried return_remarks since the return route existed and
/// nothing showed them, so a proposal came back with its state changed
/// and no reason attached.
void main() {
  Widget host(SapForm form) => ChangeNotifierProvider(
    create: (_) => AppSettings(),
    child: MaterialApp(
      theme: AppTheme.light(),
      home: SapFormScreen(form: form),
    ),
  );

  /// [by] is the server's `returned_by`: the Moderator, the Dean or the SDS
  /// Office. An older backend sends none.
  Future<SapForm> returned({String? remarks, String? by}) async {
    final body = {
      'id': 'p1',
      'event_id': 'e1',
      'state': 'revision_requested',
      'version': 4,
      'revision_no': 1,
      'details': {'title': 'Hack the Future'},
      'collections': <String, dynamic>{},
      if (remarks != null) 'return_remarks': remarks,
      'returned_by': ?by,
    };
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final form = SapForm(
      eventId: 'e1',
      service: SapService(ApiClient(httpClient: client)),
    );
    await form.load();
    return form;
  }

  testWidgets('the proposer is told what to change', (tester) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final form = await returned(
      by: 'sds',
      remarks: 'Move it to the afternoon; the morning clashes with classes.',
    );

    await tester.pumpWidget(host(form));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('Move it to the afternoon'),
      findsOneWidget,
      reason: 'the words the SDS Office actually wrote',
    );
    expect(find.textContaining('Returned by the SDS Office'), findsOneWidget);
  });

  testWidgets('and told so even when no reason was given', (tester) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    // The remarks are required on the return route, but an older row may
    // carry none. Saying nothing at all is worse than saying it came
    // back — and saying whose hands it came back from is the point of
    // returned_by, so it is the Dean here, not the SDS Office.
    final form = await returned(by: 'dean');

    await tester.pumpWidget(host(form));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Returned by the Dean'), findsOneWidget);
    expect(find.textContaining('submit it again'), findsOneWidget);
    expect(find.textContaining('SDS Office sent'), findsNothing);
  });

  testWidgets('and falls back to the SDS Office when it is not said who', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    // An older backend, and the demo, send no returned_by. Before the
    // department could send a proposal back, only the SDS Office did.
    final form = await returned();

    await tester.pumpWidget(host(form));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('The SDS Office sent this back'),
      findsOneWidget,
    );
    expect(find.textContaining('Returned by'), findsNothing);
  });

  testWidgets('and so does the demo, whose returned proposal never says who', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final form = SapForm(eventId: 'e1')
      ..seedLocally(
        state: SapState.revisionRequested,
        returnRemarks: 'Fix the budget.',
      );

    await tester.pumpWidget(host(form));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('The SDS Office sent this back: Fix the budget.'),
      findsOneWidget,
    );
    expect(find.textContaining('Returned by'), findsNothing);
  });

  testWidgets('with the words it was sent back with, when it has them', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final form = await returned(remarks: 'Fix the budget.');

    await tester.pumpWidget(host(form));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('The SDS Office sent this back: Fix the budget.'),
      findsOneWidget,
    );
  });

  testWidgets('and can still edit and resubmit it', (tester) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final form = await returned(remarks: 'Fix the budget.');

    expect(form.canEditProposerParts, isTrue);
    expect(form.wasReturned, isTrue);

    await tester.pumpWidget(host(form));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Submit for review'),
      findsOneWidget,
      reason: 'a returned proposal goes back the same way it went first',
    );
  });
}
