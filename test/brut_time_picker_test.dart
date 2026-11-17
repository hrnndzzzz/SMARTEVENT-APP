import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/state/school_calendar.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/widgets/brut_time_picker.dart';

/// The app's own clock: three columns, an arrow above and below each.
///
/// Material's dial offered all twenty-four hours and the window was
/// enforced after it closed, so the way to find out a time was refused
/// was to pick it. Here the arrow that would leave the window is grey,
/// which is the rule before the mistake rather than after it.
void main() {
  /// Opened the way the app opens it: a modal sheet over a Scaffold.
  ///
  /// Not as a bare Scaffold body, which is how this was written first
  /// — and why a refusal shown in a snackbar passed its test while
  /// being invisible on the phone, drawn underneath the sheet that
  /// provoked it.
  Future<void> open(WidgetTester tester, {SapTime? initial}) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => BrutTimePicker.show(
                  context,
                  initial: initial,
                  earliest: SchoolCalendar.earliest,
                  latest: SchoolCalendar.latest,
                ),
                child: const Text('open it'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open it'));
    await tester.pumpAndSettle();
  }

  Finder arrow(String label) =>
      find.byWidgetPredicate((w) => w is BrutIconButton && w.label == label);

  /// How available an arrow looks. Every one is pressable now; the
  /// dimming is what says the answer will be no before the press.
  double dimming(WidgetTester tester, String label) => tester
      .widget<Opacity>(
        find.ancestor(of: arrow(label), matching: find.byType(Opacity)).first,
      )
      .opacity;

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(arrow(label));
    await tester.pumpAndSettle();
  }

  testWidgets('it opens at the start of the window and cannot go below it', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Use 6:00 AM'), findsOneWidget);

    // The fault this replaced: a proposal could say an activity began
    // at 12:00 AM, which is not a time anybody holds one at — it is
    // what a dial returns when somebody taps through it.
    expect(dimming(tester, 'Hour down'), lessThan(1));
    expect(dimming(tester, 'Minutes down'), lessThan(1));

    // And pressing one says what is in the way rather than doing
    // nothing at all.
    await press(tester, 'Hour down');
    expect(find.text('Use 6:00 AM'), findsOneWidget, reason: 'it moved');
    expect(
      find.descendant(
        of: find.byType(BrutTimePicker),
        matching: find.textContaining('is outside'),
      ),
      findsOneWidget,
      reason: 'said somewhere other than in the sheet it was said about',
    );
  });

  testWidgets('the arrows move it by an hour and by a quarter', (tester) async {
    await open(tester);

    await press(tester, 'Hour up');
    expect(find.text('Use 7:00 AM'), findsOneWidget);

    await press(tester, 'Minutes up');
    expect(find.text('Use 7:15 AM'), findsOneWidget);

    await press(tester, 'Minutes down');
    expect(find.text('Use 7:00 AM'), findsOneWidget);
  });

  testWidgets('it cannot be stepped past the end of the window', (
    tester,
  ) async {
    await open(tester, initial: const SapTime(22, 0));
    expect(find.text('Use 10:00 PM'), findsOneWidget);

    // 10:15 PM and 11:00 PM are both outside it, so neither arrow is
    // live. Greyed rather than missing: an arrow that vanishes makes
    // the column change shape.
    expect(dimming(tester, 'Minutes up'), lessThan(1));
    expect(dimming(tester, 'Hour up'), lessThan(1));
    expect(dimming(tester, 'Hour down'), 1);
  });

  testWidgets('the half-day arrow only goes the way the window allows', (
    tester,
  ) async {
    await open(tester, initial: const SapTime(8, 0));
    expect(find.text('AM'), findsOneWidget);

    // 8:00 PM is inside the window, so this one moves.
    await press(tester, 'AM or PM down');
    expect(find.text('Use 8:00 PM'), findsOneWidget);
    expect(find.text('PM'), findsOneWidget);

    // 8:00 AM is as well, so it comes back.
    await press(tester, 'AM or PM up');
    expect(find.text('Use 8:00 AM'), findsOneWidget);
  });

  testWidgets('a time already saved off the quarter keeps it', (tester) async {
    // Rounding a record silently is the display lying about the data.
    await open(tester, initial: const SapTime(8, 5));
    expect(find.text('Use 8:05 AM'), findsOneWidget);
    expect(find.text('05'), findsOneWidget);
  });

  testWidgets('a time from outside the window opens inside it', (tester) async {
    // However it got into the record, it is not a starting point — and
    // clamping the hour alone would turn 2:30 AM into 6:30 AM, a time
    // nobody chose wearing the look of one somebody did.
    await open(tester, initial: const SapTime(2, 30));
    expect(find.text('Use 6:00 AM'), findsOneWidget);
  });

  testWidgets('noon says why it cannot change half of the day', (tester) async {
    // The case that made all of this speak up. At 12 PM both half-day
    // arrows are stuck — 12 AM is before the window and the next
    // midnight is after it — and two dead arrows at once read as
    // broken rather than as a limit.
    await open(tester, initial: const SapTime(12, 0));
    expect(find.text('Use 12:00 PM'), findsOneWidget);
    expect(dimming(tester, 'AM or PM up'), lessThan(1));
    expect(dimming(tester, 'AM or PM down'), lessThan(1));

    await press(tester, 'AM or PM up');

    expect(find.text('Use 12:00 PM'), findsOneWidget, reason: 'it moved');
    // Inside the picker, not in a snackbar: a snackbar belongs to the
    // Scaffold and this sheet is drawn over the bottom of it, so the
    // message would be underneath the arrow that caused it.
    expect(
      find.descendant(
        of: find.byType(BrutTimePicker),
        matching: find.text('12:00 AM is outside 6:00 AM – 10:00 PM.'),
      ),
      findsOneWidget,
      reason: 'it refused without saying why, where it could be seen',
    );
  });
}
