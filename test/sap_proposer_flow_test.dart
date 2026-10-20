import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_proposer_flow_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

Widget host(SapForm form) => MaterialApp(
  theme: AppTheme.light(),
  home: SapProposerFlowScreen(form: form),
);

void main() {
  testWidgets('a proposer is shown three steps, not six', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    await tester.pumpWidget(host(SapForm(eventId: 'e1')));
    await tester.pumpAndSettle();

    // The current step's name is in the header as well as its row, so
    // the first of these legitimately appears twice.
    expect(find.text('Activity Details'), findsWidgets);
    expect(find.text('School Support'), findsOneWidget);
    expect(find.text('Additional Information'), findsOneWidget);

    // Parts 4 to 6 are the SDS Office's and must not appear as steps
    // somebody is expected to complete.
    expect(find.text('SDS Office Clearance'), findsNothing);
    expect(find.text('University Clearance'), findsNothing);
    expect(find.text('Evaluation'), findsNothing);
  });

  testWidgets('sending is refused until all three are filled in', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    final form = SapForm(eventId: 'e1');
    await tester.pumpWidget(host(form));
    await tester.pumpAndSettle();

    final send = find.widgetWithText(BrutButton, 'Send to the SDS Office');
    expect(send, findsOneWidget);
    expect(tester.widget<BrutButton>(send).onPressed, isNull);
    expect(find.text('0 OF 3 FILLED IN'), findsOneWidget);
  });

  testWidgets('once it is under review the proposer only sees where it is', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    final form = SapForm(eventId: 'e1')
      ..adoptForTest(state: SapState.pendingReview);

    await tester.pumpWidget(host(form));
    await tester.pumpAndSettle();

    expect(find.text('With the SDS Office'), findsOneWidget);
    expect(find.text('Activity Details'), findsNothing);
  });
}
