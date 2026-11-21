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

import 'support/complete_proposal.dart';

/// A program flow document stands in for the rows, the budget has a
/// ceiling and a balance to fit, and a budget line has a button to edit it.
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

  test('the budget has a ceiling and must fit what is left', () {
    final form = filledIn(SapForm());
    form.updateDetails((d) => d.copyWith(totalBudget: '1000000.00'));
    expect(form.missingForSubmit, contains(SapForm.budgetCapLabel));

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
      of: find.widgetWithText(BrutTextField, 'AMOUNT'),
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
