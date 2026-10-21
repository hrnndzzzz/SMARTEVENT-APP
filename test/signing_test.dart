import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/screens/sap/sds_sign_screen.dart';
import 'package:smartevent/screens/sap/signature_pad.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// The one electronic signature on the form.
///
/// What matters here is that the drawing leaves normalised, that a
/// drawing the server would refuse cannot be sent, and that signing —
/// which cannot be undone — asks first.
Widget host(Widget child) =>
    MaterialApp(theme: AppTheme.light(), home: child);

void main() {
  group('the pad', () {
    testWidgets('says what it is for before anything is drawn', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(Scaffold(body: SapSignaturePad(onChanged: (_) {}))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign here'), findsOneWidget);
    });

    testWidgets('a drawn stroke comes back normalised', (tester) async {
      SapSignature? captured;

      await tester.pumpWidget(
        host(
          Scaffold(
            body: SizedBox(
              width: 400,
              child: SapSignaturePad(
                height: 200,
                onChanged: (s) => captured = s,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Inside the drawing area, not the centre of the whole widget —
      // that falls on the undo and clear row below the canvas.
      final origin =
          tester.getTopLeft(find.byType(SapSignaturePad)) +
          const Offset(40, 60);
      await tester.dragFrom(origin, const Offset(50, 30));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.strokes, hasLength(1));
      for (final point in captured!.strokes.single) {
        expect(point.isNormalised, isTrue, reason: '${point.x}, ${point.y}');
      }
      expect(captured!.isSendable, isTrue);
    });

    testWidgets('undo and clear are dead until there is something to undo', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(Scaffold(body: SapSignaturePad(onChanged: (_) {}))),
      );
      await tester.pumpAndSettle();

      for (final label in ['Undo stroke', 'Clear']) {
        final button = tester.widget<BrutButton>(
          find.widgetWithText(BrutButton, label),
        );
        expect(button.onPressed, isNull, reason: label);
      }
    });

    testWidgets('a closed pad says so and cannot be drawn on', (
      tester,
    ) async {
      SapSignature? captured;

      await tester.pumpWidget(
        host(
          Scaffold(
            body: SapSignaturePad(
              enabled: false,
              onChanged: (s) => captured = s,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Signing is closed'), findsOneWidget);

      final origin =
          tester.getTopLeft(find.byType(SapSignaturePad)) +
          const Offset(40, 60);
      await tester.dragFrom(origin, const Offset(40, 20));
      await tester.pumpAndSettle();

      expect(captured, isNull);
    });
  });

  group('getting there', () {
    testWidgets('the hub offers it while the office is waiting', (
      tester,
    ) async {
      final form = SapForm(eventId: 'e1')
        ..adoptForTest(state: SapState.pendingReview);

      await tester.pumpWidget(host(SapFormScreen(form: form)));
      await tester.pumpAndSettle();

      expect(find.text('Review and sign'), findsOneWidget);
    });

    testWidgets('and does not while it is still a draft', (tester) async {
      await tester.pumpWidget(
        host(SapFormScreen(form: SapForm(eventId: 'e1'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review and sign'), findsNothing);
    });
  });

  group('the screen', () {
    SapForm pending() {
      final form = SapForm(eventId: 'e1');
      form.adoptForTest(state: SapState.pendingReview);
      return form;
    }

    testWidgets('will not sign until something is drawn', (tester) async {
      await tester.pumpWidget(host(SdsSignScreen(form: pending())));
      await tester.pumpAndSettle();

      final button = tester.widget<BrutButton>(
        find.widgetWithText(BrutButton, 'Sign the proposal'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('offers a remark against every section the server takes', (
      tester,
    ) async {
      await tester.pumpWidget(host(SdsSignScreen(form: pending())));
      await tester.pumpAndSettle();

      for (final section in SapRemarkSection.values) {
        expect(
          find.text(section.label.toUpperCase()),
          findsOneWidget,
          reason: section.wireName,
        );
      }
    });

    testWidgets('a signed revision is closed to further signing', (
      tester,
    ) async {
      final form = SapForm(eventId: 'e1')
        ..adoptForTest(state: SapState.sdsSigned);

      await tester.pumpWidget(host(SdsSignScreen(form: form)));
      await tester.pumpAndSettle();

      expect(find.textContaining('This revision is signed'), findsOneWidget);
      expect(find.text('Signing is closed'), findsOneWidget);
    });

    testWidgets('a draft is not something to review', (tester) async {
      await tester.pumpWidget(
        host(SdsSignScreen(form: SapForm(eventId: 'e1'))),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Only a proposal waiting on the SDS Office'),
        findsOneWidget,
      );
    });
  });
}
