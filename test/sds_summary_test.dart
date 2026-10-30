import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sds_summary_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// What the SDS Office opens.
///
/// It was the six-part form, which asked the office to walk a form that
/// is already written. What they have to do is read it, decide, and
/// sign.
void main() {
  Widget host(SapForm form) => ChangeNotifierProvider(
    create: (_) => AppSettings(),
    child: MaterialApp(
      theme: AppTheme.light(),
      home: SdsSummaryScreen(form: form),
    ),
  );

  SapForm filled({SapState state = SapState.pendingReview}) {
    final form = SapForm(eventId: 'e1')..seedLocally(state: state);
    form.updateDetails(
      (d) => d.copyWith(
        title: 'HACK THE FUTURE',
        organizationName: 'ACPES',
        schoolYear: '2026-2027',
        venue: 'St. Augustine AVR',
        expectedStudents: 145,
        totalBudget: '2500.00',
        setting: SapSetting.onCampus,
        rationale: 'Because the students asked for it.',
      ),
    );
    form.setBudgetItems(const [
      SapBudgetItem(particulars: 'Snacks', amount: '1500.00'),
      SapBudgetItem(particulars: 'Materials', amount: '1000.00'),
    ]);
    return form;
  }

  testWidgets('it reads as a summary, not a form to fill in', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(host(filled()));
    await tester.pumpAndSettle();

    expect(find.text('HACK THE FUTURE'), findsOneWidget);
    expect(find.textContaining('St. Augustine AVR'), findsOneWidget);
    expect(find.textContaining('145'), findsWidgets);

    // Not the six-part list.
    expect(find.text('Activity Details'), findsNothing);
    expect(find.text('School Support'), findsNothing);
  });

  testWidgets('the budget and its lines are both there', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(host(filled()));
    await tester.pumpAndSettle();

    expect(find.text('Snacks'), findsOneWidget);
    expect(find.text('Materials'), findsOneWidget);
  });

  testWidgets('a breakdown that does not add up is said so', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    final form = filled();
    // The server refuses this, so the office should see it before it
    // decides rather than after.
    form.updateDetails((d) => d.copyWith(totalBudget: '9999.00'));

    await tester.pumpWidget(host(form));
    await tester.pumpAndSettle();

    expect(find.textContaining('is not the total'), findsOneWidget);
  });

  testWidgets('a waiting proposal offers to sign', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(host(filled()));
    await tester.pumpAndSettle();

    expect(find.text('Review and sign'), findsOneWidget);
  });

  /// The list hands over a form nobody has loaded yet.
  SapForm fromServer() => SapForm(
    eventId: 'e1',
    service: SapService(
      ApiClient(
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'id': 'p1',
              'event_id': 'e1',
              'state': 'pending_sap_review',
              'version': 4,
              'revision_no': 1,
              'details': {'title': 'HACK THE FUTURE'},
              'sds_review': {
                'overall_remarks': 'Please revise the food budget.',
                'section_remarks': {'budget': 'Meals are over the allowance.'},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    ),
  );

  testWidgets('it loads the proposal itself on opening', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(host(fromServer()));
    await tester.pumpAndSettle();

    expect(find.text('HACK THE FUTURE'), findsOneWidget);
    expect(find.text('Review and sign'), findsOneWidget);
  });

  testWidgets('remarks saved earlier are there to carry on with', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(host(fromServer()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review and sign'));
    await tester.pumpAndSettle();

    expect(find.text('Please revise the food budget.'), findsOneWidget);
    expect(find.text('Meals are over the allowance.'), findsOneWidget);
  });

  testWidgets('and one already signed does not', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(host(filled(state: SapState.sdsSigned)));
    await tester.pumpAndSettle();

    expect(find.text('Review and sign'), findsNothing);
    expect(find.text('Open the full form'), findsOneWidget);
  });
}
