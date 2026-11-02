import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// F13, tagging a resubmission, and F11, a concluded event waiting on
/// its evaluation.
///
/// Both were filed as blocked on backend states. Neither needed one: a
/// submit bumps `revision_no`, so a revision above one already says the
/// proposal was sent twice, and an approved proposal with no evaluation
/// is already a proposal waiting to be evaluated.
void main() {
  Widget host(SapForm form) => ChangeNotifierProvider(
    create: (_) => AppSettings(),
    child: MaterialApp(
      theme: AppTheme.light(),
      home: SapFormScreen(form: form),
    ),
  );

  Future<SapForm> proposal({
    required String state,
    required int revisionNo,
    bool evaluated = false,
  }) async {
    final body = {
      'id': 'p1',
      'event_id': 'e1',
      'state': state,
      'version': 6,
      'revision_no': revisionNo,
      'details': {'title': 'Hack the Future'},
      'collections': <String, dynamic>{},
      if (evaluated)
        'evaluation': {'outcome': 'conducted', 'remarks': 'It ran well.'},
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

  Future<void> open(WidgetTester tester, SapForm form) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(form));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a second submission says which revision it is', (tester) async {
    final form = await proposal(state: 'pending_sap_review', revisionNo: 2);

    expect(form.isResubmission, isTrue);
    await open(tester, form);

    expect(find.textContaining('REVISION 2'), findsOneWidget);
  });

  testWidgets('a resubmission goes back to the department first', (
    tester,
  ) async {
    // Sending it again starts the round again: the Moderator and Dean
    // see revision 2 before the SDS Office does.
    final form = await proposal(
      state: 'pending_department_review',
      revisionNo: 2,
    );

    expect(form.isResubmission, isTrue);
    await open(tester, form);

    expect(find.textContaining('REVISION 2'), findsOneWidget);
    expect(find.textContaining('With the Moderator and Dean'), findsOneWidget);
    expect(find.textContaining('sent this back'), findsNothing);
  });

  testWidgets('a first submission says nothing about revisions', (
    tester,
  ) async {
    final form = await proposal(state: 'pending_sap_review', revisionNo: 1);

    expect(form.isResubmission, isFalse);
    await open(tester, form);

    expect(find.textContaining('REVISION'), findsNothing);
  });

  testWidgets('an approved proposal waits on its evaluation', (tester) async {
    final form = await proposal(state: 'approved', revisionNo: 1);

    expect(form.awaitingEvaluation, isTrue);
    await open(tester, form);

    expect(find.textContaining('Waiting on the SDS Office'), findsOneWidget);
  });

  testWidgets('and stops saying so once it is recorded', (tester) async {
    final form = await proposal(
      state: 'completed',
      revisionNo: 1,
      evaluated: true,
    );

    expect(form.awaitingEvaluation, isFalse);
    await open(tester, form);

    expect(find.textContaining('Waiting on the SDS Office'), findsNothing);
  });
}
