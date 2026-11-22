import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/proposal_steps.dart';
import 'package:smartevent/screens/sap/sap_part3_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/widgets/brut_amount_field.dart';

import 'support/complete_proposal.dart';

/// A program flow document stands in for the rows, the budget has a
/// balance to fit, and a budget line has a button to edit it.
void main() {
  /// A draft whose files, once one is sent, are a program flow document.
  SapService server() => SapService(
    ApiClient(
      httpClient: MockClient((request) async {
        final Object body =
            request.method == 'GET' && request.url.path.endsWith('/attachments')
            ? [
                {'id': 'a1', 'category': 'program_flow', 'file_name': 'f.pdf'},
              ]
            : {
                'id': 'p1',
                'event_id': 'e1',
                'state': 'draft',
                'version': 1,
                'revision_no': 0,
                'details': <String, Object>{},
                'collections': {
                  'program-flow': <Object>[],
                  'budget-items': <Object>[],
                  'support-requests': <Object>[],
                  'affected-classes': <Object>[],
                },
              };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );

  test('a program flow document is enough without rows', () async {
    final form = SapForm(eventId: 'e1', service: server());
    await form.load();
    filledIn(form).setProgramFlow([]);
    expect(form.missingForSubmit, contains('Program flow'));

    final problem = await form.attachFile(
      category: SapAttachmentCategory.programFlow,
      bytes: utf8.encode('%PDF-1.4 test'),
      filename: 'f.pdf',
    );
    expect(problem, isNull);
    expect(form.hasProgramFlowFile, isTrue);
    expect(form.missingForSubmit, isEmpty);
  });

  test('the budget has no fixed ceiling, only what is left', () {
    // Large, but covered: nothing refuses it for its size alone.
    final large = filledIn(SapForm())..availableBudget = 2000000;
    large.updateDetails((d) => d.copyWith(totalBudget: '1500000.00'));
    large.setBudgetItems([
      SapBudgetItem.fromJson(const {
        'particulars': 'Venue',
        'amount': '1500000.00',
      }),
    ]);
    expect(large.missingForSubmit, isEmpty);

    final fits = filledIn(SapForm())..availableBudget = 2500;
    expect(fits.missingForSubmit, isEmpty);
    final over = filledIn(SapForm())..availableBudget = 2000;
    final label = over.missingForSubmit.single;
    expect(label, 'Budget within the available ₱2,000.00');
    expect(
      ProposalSteps.stepForMissing(label),
      ProposalSteps.breakdown,
      reason: 'it blocks sending, not saving the step',
    );
  });

  test('the number of students is held to what the setting allows', () {
    expect(SapForm.studentsOver(SapSetting.onCampus, 10000), isNull);
    expect(SapForm.studentsOver(SapSetting.onCampus, 10001), '10,000');
    expect(SapForm.studentsOver(SapSetting.offCampus, 500), isNull);
    expect(SapForm.studentsOver(SapSetting.offCampus, 501), '500');
    expect(SapForm.studentsOver(SapSetting.online, 5001), '5,000');
    expect(SapForm.studentsOver(null, 100000), isNull);

    final form = filledIn(SapForm()); // online
    form.updateDetails((d) => d.copyWith(expectedStudents: 5001));
    final label = form.missingForSubmit.single;
    expect(label, 'Number of students: at most 5,000 online');
    expect(ProposalSteps.stepForMissing(label), ProposalSteps.details);
  });

  testWidgets('a budget line has a button that edits it in place', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final form = filledIn(SapForm());
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SapPart3Screen(form: form),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final amount = find.descendant(
      of: find.byType(BrutAmountField),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(amount).controller!.text, '2500.00');
    await tester.enterText(amount, '2400.00');
    await tester.pump();
    // The sheet's, over the screen's own Save.
    await tester.tap(find.widgetWithText(BrutButton, 'Save').last);
    await tester.pumpAndSettle();

    expect(form.budgetItems, hasLength(1));
    expect(form.budgetItems.single.particulars, 'Speaker');
    expect(form.budgetItems.single.amount, '2400.00');
  });
}
