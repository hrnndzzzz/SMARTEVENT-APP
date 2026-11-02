import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/state/app_state.dart' show AppState, UserRole;
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// The demo offers the SDS role "all six parts of the proposal form".
///
/// Without a server the form held no proposal and sat at a null state,
/// which locks Parts 5 and 6 and hides review and signing — so the role
/// showed four parts and two closed rows, and three screens could not be
/// looked at on a phone at all.
Widget host(Widget child) => ChangeNotifierProvider.value(
  // Review and signing are the SDS Office's, so the demo role that is
  // offered them is the one hosting the hub.
  value: AppState()..enterDemo(role: UserRole.sdsStaff),
  child: MaterialApp(theme: AppTheme.light(), home: child),
);

void main() {
  test('a form with no server still starts where it is put', () {
    final form = SapForm(eventId: 'e1')
      ..seedLocally(state: SapState.pendingReview);

    expect(form.state, SapState.pendingReview);

    // Still local-only: there is no server behind it, so anything that
    // needs one — printing the PDF, above all — stays shut. Seeding
    // opens the screens, it does not pretend there is a backend.
    expect(form.isLocalOnly, isTrue);
  });

  testWidgets('a proposal with the office opens Part 5', (tester) async {
    final form = SapForm(eventId: 'e1')
      ..seedLocally(state: SapState.pendingReview);

    await tester.pumpWidget(host(SapFormScreen(form: form)));
    await tester.pumpAndSettle();

    // Part 5 opens; Part 6 is the evaluation and stays shut until the
    // activity has been approved, so exactly one row reads "Not yet".
    expect(find.text('Not yet'), findsOneWidget);
  });

  testWidgets('and an approved one opens Part 6 as well', (tester) async {
    final form = SapForm(eventId: 'e1')
      ..seedLocally(state: SapState.approved);

    await tester.pumpWidget(host(SapFormScreen(form: form)));
    await tester.pumpAndSettle();

    expect(find.text('Not yet'), findsNothing);
  });

  testWidgets('and shows the way into review and signing', (tester) async {
    final form = SapForm(eventId: 'e1')
      ..seedLocally(state: SapState.pendingReview);

    await tester.pumpWidget(host(SapFormScreen(form: form)));
    await tester.pumpAndSettle();

    expect(find.text('Review and sign'), findsOneWidget);
  });

  testWidgets('a draft still keeps the SDS parts shut', (tester) async {
    final form = SapForm(eventId: 'e1')..seedLocally(state: SapState.draft);

    await tester.pumpWidget(host(SapFormScreen(form: form)));
    await tester.pumpAndSettle();

    expect(find.text('Not yet'), findsWidgets);
    expect(find.text('Review and sign'), findsNothing);
  });
}
