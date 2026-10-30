import 'package:flutter/gestures.dart';
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

    testWidgets('a cancelled stroke is still kept', (tester) async {
      // A pointer that is cancelled rather than lifted still keeps what
      // was drawn. It does so through onEnd: once a drag is accepted,
      // Flutter turns a cancelled pointer into an end, and onPanCancel
      // fires only for a drag that was never accepted — which has no
      // stroke to lose. Worth pinning, because that is not obvious and
      // it is the difference between a kept signature and a lost one.
      SapSignature? captured;

      await tester.pumpWidget(
        host(
          Scaffold(
            body: SapSignaturePad(onChanged: (s) => captured = s),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final origin =
          tester.getTopLeft(find.byType(SapSignaturePad)) +
          const Offset(40, 60);

      // A raw PointerCancelEvent, not gesture.cancel(): that one
      // reaches the recognizer as an end, so it never exercises the
      // cancel path at all.
      const pointer = 7;
      final down = PointerDownEvent(pointer: pointer, position: origin);
      tester.binding.handlePointerEvent(down);
      tester.binding.handlePointerEvent(
        PointerMoveEvent(
          pointer: pointer,
          position: origin + const Offset(30, 20),
          delta: const Offset(30, 20),
        ),
      );
      await tester.pump();
      tester.binding.handlePointerEvent(
        PointerCancelEvent(
          pointer: pointer,
          position: origin + const Offset(30, 20),
        ),
      );
      await tester.pumpAndSettle();

      expect(captured, isNotNull, reason: 'the stroke was drawn');
      expect(captured!.isSendable, isTrue);

      final clear = tester.widget<BrutButton>(
        find.widgetWithText(BrutButton, 'Clear'),
      );
      expect(clear.onPressed, isNotNull, reason: 'there is ink to clear');
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
        ..seedLocally(state: SapState.pendingReview);

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

  group('inside the page it actually lives on', () {
    // Every other test here puts the pad in a bare Scaffold. On the real
    // screen it sits in a scroll view, and a vertical stroke is a
    // vertical drag: the scrollable used to win that contest, so the
    // page scrolled and the stroke was never drawn. Downstrokes are
    // most of a signature, so this lost most of one.
    Future<SapSignature?> drawInScrollView(
      WidgetTester tester,
      Offset step,
    ) async {
      SapSignature? captured;

      await tester.pumpWidget(
        host(
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 200),
                  SapSignaturePad(onChanged: (s) => captured = s),
                  const SizedBox(height: 1400),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final origin =
          tester.getTopLeft(find.byType(SapSignaturePad)) +
          const Offset(40, 60);

      final gesture = await tester.startGesture(origin);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(step);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      return captured;
    }

    testWidgets('a downstroke is kept, not given to the scroll view', (
      tester,
    ) async {
      final signature = await drawInScrollView(tester, const Offset(0, 10));

      expect(signature, isNotNull, reason: 'the page scrolled instead');
      expect(signature!.strokes, hasLength(1));
      expect(signature.isSendable, isTrue);
    });

    testWidgets('and so are the other directions', (tester) async {
      for (final step in [Offset(10, 0), Offset(8, 6), Offset(-6, 9)]) {
        final signature = await drawInScrollView(tester, step);
        expect(signature?.isSendable, isTrue, reason: '$step');
      }
    });
  });

  group('the screen', () {
    SapForm pending({bool cleared = true}) {
      final form = SapForm(eventId: 'e1');
      if (cleared) {
        form.setClearance(
          const SapClearance(
            parentsConsent: SapClearanceAnswer.yes,
            attachments: 'Program and budget',
            classInterruption: SapClearanceAnswer.none,
            medicalExam: SapClearanceAnswer.yes,
            reportOfCompliance: SapClearanceAnswer.yes,
            studentPersonnelRatio: '145:3',
          ),
        );
      }
      form.seedLocally(state: SapState.pendingReview);
      return form;
    }

    testWidgets('will not sign until something is drawn', (tester) async {
      await tester.pumpWidget(host(SdsSignScreen(form: pending())));
      await tester.pumpAndSettle();

      final button = tester.widget<BrutButton>(
        find.widgetWithText(BrutButton, 'Sign the proposal'),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('Confirm Part 4'), findsNothing);
    });

    testWidgets('will not sign until Part 4 is confirmed', (tester) async {
      await tester.pumpWidget(
        host(SdsSignScreen(form: pending(cleared: false))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Confirm Part 4'), findsOneWidget);
      expect(
        tester
            .widget<SapSignaturePad>(find.byType(SapSignaturePad))
            .enabled,
        isFalse,
      );
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
        ..seedLocally(state: SapState.sdsSigned);

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
