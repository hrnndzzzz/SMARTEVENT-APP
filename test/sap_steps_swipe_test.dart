import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/screens/sap/sap_steps_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// The three steps are one screen with three pages.
///
/// They were three pushed routes, so going from the breakdown back to
/// check something on the activity meant backing out of two screens and
/// finding the way in again.
void main() {
  /// [created] says whether the event record was made: the flow binds the
  /// form to it on success, so the stub does the same.
  Widget host(
    SapForm form, {
    VoidCallback? onCreate,
    VoidCallback? onSubmit,
    bool created = true,
  }) => MaterialApp(
    theme: AppTheme.light(),
    home: SapStepsScreen(
      form: form,
      onCreateEvent: (_) async {
        onCreate?.call();
        if (created) await form.bindEvent('e1');
        return created;
      },
      onSubmit: (_) async => onSubmit?.call(),
    ),
  );

  testWidgets('it opens on the activity', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(host(SapForm(eventId: 'e1')));
    await tester.pumpAndSettle();

    expect(find.text('Activity Details'), findsOneWidget);
  });

  testWidgets('a swipe reaches the support step', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(host(SapForm(eventId: 'e1')));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('School Support'), findsOneWidget);
  });

  testWidgets('and a swipe back reaches the activity again', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(host(SapForm(eventId: 'e1')));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Activity Details'), findsOneWidget);
  });

  testWidgets('the support step can reach either of its neighbours', (
    tester,
  ) async {
    // What was asked for: from the middle, both directions.
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(host(SapForm(eventId: 'e1')));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('School Support'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('Additional Information'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('School Support'), findsOneWidget);
  });

  testWidgets('swiping off the activity still makes the event record', (
    tester,
  ) async {
    // Pressing Next did it. Swiping past would have skipped it, and the
    // submission at the end would have had nothing to attach to.
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    var created = 0;

    await tester.pumpWidget(host(SapForm(), onCreate: () => created++));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();

    expect(created, 1);
  });

  testWidgets('and does not ask for it again on every swipe', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    var created = 0;

    await tester.pumpWidget(host(SapForm(), onCreate: () => created++));
    await tester.pumpAndSettle();

    for (final delta in [-400.0, 400.0, -400.0, -400.0]) {
      await tester.fling(find.byType(PageView), Offset(delta, 0), 1200);
      await tester.pumpAndSettle();
    }

    expect(created, 1);
  });

  testWidgets('a refused event record keeps the swipe on the activity', (
    tester,
  ) async {
    // The server refused it — no organization, say. Past Part 1 nothing
    // could be sent, and the form used to carry on as though it could.
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    final form = SapForm();
    await tester.pumpWidget(host(form, created: false));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Activity Details'), findsOneWidget);
    expect(form.hasEvent, isFalse);
  });

  testWidgets('and the next attempt asks again', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    var attempts = 0;
    await tester.pumpWidget(
      host(SapForm(), created: false, onCreate: () => attempts++),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 2; i++) {
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
      await tester.pumpAndSettle();
    }

    expect(attempts, 2);
  });

  testWidgets('all three exist at once, not pushed one at a time', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(host(SapForm(eventId: 'e1')));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
  });
}
