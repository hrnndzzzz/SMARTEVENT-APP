import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/state/school_calendar.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/widgets/brut_time_picker.dart';

/// The app's own clock.
///
/// Material's dial offered all twenty-four hours and the window was
/// enforced after it closed, so the way to find out a time was refused
/// was to pick it. This one does not offer what it will not take.
void main() {
  Widget host({SapTime? initial}) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: BrutTimePicker(
        initial: initial,
        earliest: SchoolCalendar.earliest,
        latest: SchoolCalendar.latest,
      ),
    ),
  );

  /// The chips that can still be pressed.
  List<BrutChip> live(WidgetTester tester) => [
    for (final chip in tester.widgetList<BrutChip>(find.byType(BrutChip)))
      if (chip.onTap != null) chip,
  ];

  testWidgets('midnight is not on offer at all', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // The fault this replaced: a proposal could say an activity began
    // at 12:00 AM, which is not a time anybody holds one at — it is
    // what a dial returns when somebody taps through it.
    expect(find.text('12 AM'), findsNothing);
    expect(find.text('11 PM'), findsNothing);
    expect(find.text('6 AM'), findsOneWidget);
    expect(find.text('10 PM'), findsOneWidget);
  });

  testWidgets('the last hour offers only the minute it can reach', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('10 PM'));
    await tester.pumpAndSettle();

    // 10:15 PM is past the end, so the chip is shown and refused
    // rather than missing: the end of the window is a thing to see.
    final labels = live(tester).map((c) => c.label).toSet();
    expect(labels.contains(':00'), isTrue);
    expect(labels.contains(':15'), isFalse);
    expect(labels.contains(':45'), isFalse);
    expect(find.text(':15'), findsOneWidget, reason: 'it should still show');
  });

  testWidgets('a minute that cannot survive the hour does not follow it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(initial: const SapTime(9, 45)));
    await tester.pumpAndSettle();
    expect(find.text('Use 9:45 AM'), findsOneWidget);

    await tester.tap(find.text('10 PM'));
    await tester.pumpAndSettle();

    expect(
      find.text('Use 10:00 PM'),
      findsOneWidget,
      reason: '10:45 PM is past the end of the window',
    );
  });

  testWidgets('a time already saved off the quarter keeps it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Rounding a record silently is the display lying about the data.
    await tester.pumpWidget(host(initial: const SapTime(8, 5)));
    await tester.pumpAndSettle();

    expect(find.text(':05'), findsOneWidget);
    expect(find.text('Use 8:05 AM'), findsOneWidget);
  });

  testWidgets('a time from outside the window opens inside it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // However it got into the record, it is not a starting point.
    await tester.pumpWidget(host(initial: const SapTime(2, 30)));
    await tester.pumpAndSettle();

    expect(find.text('Use 6:00 AM'), findsOneWidget);
  });
}
