import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/screens/sap/sap_part5_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// Printing the form, and saying truthfully what comes out.
///
/// `73a23b0` changed what `GET /pdf` returns: once the SDS Office has
/// signed a revision, the server hands back the stored signed copy with
/// its own watermark. The hub still told people the printout "stays an
/// unsigned copy even after approval", which stopped being true.
Widget host(Widget child) =>
    MaterialApp(theme: AppTheme.light(), home: child);

SapForm at(SapState state) =>
    SapForm(eventId: 'e1')..seedLocally(state: state);

void main() {
  group('what the hub says it will print', () {
    testWidgets('a working copy while it is still being filled in', (
      tester,
    ) async {
      await tester.pumpWidget(host(SapFormScreen(form: at(SapState.draft))));
      await tester.pumpAndSettle();

      expect(find.textContaining('six-page layout'), findsOneWidget);
      expect(find.textContaining('signed form'), findsNothing);
    });

    testWidgets('the signed form once the office has signed', (tester) async {
      await tester.pumpWidget(
        host(SapFormScreen(form: at(SapState.sdsSigned))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('signed form the SDS Office stored'),
          findsOneWidget);
    });

    testWidgets('and never claims it stays unsigned', (tester) async {
      for (final state in SapState.values) {
        await tester.pumpWidget(host(SapFormScreen(form: at(state))));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('stays an unsigned copy'),
          findsNothing,
          reason: '${state.wireName} still claims it',
        );
      }
    });
  });

  group('Part 5', () {
    testWidgets('offers the printout where the paper is collected', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(SapPart5Screen(form: at(SapState.pendingReview))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Print for the signatories'), findsOneWidget);
    });

    testWidgets('and says whose copy it is once signed', (tester) async {
      await tester.pumpWidget(
        host(SapPart5Screen(form: at(SapState.sdsSigned))),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The SDS Office has signed'),
        findsOneWidget,
      );
    });

    testWidgets('a form with no server behind it cannot print', (
      tester,
    ) async {
      final form = SapForm();
      await tester.pumpWidget(host(SapPart5Screen(form: form)));
      await tester.pumpAndSettle();

      final button = tester.widget<BrutButton>(
        find.widgetWithText(BrutButton, 'Print for the signatories'),
      );
      expect(button.onPressed, isNull);
    });
  });
}
