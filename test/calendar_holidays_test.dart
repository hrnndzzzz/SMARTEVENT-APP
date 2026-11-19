import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartevent/state/school_calendar.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/widgets/month_grid.dart';

/// The holidays reach the month grid.
///
/// SchoolCalendar has computed them since it was written, and the
/// proposal picker has refused them for just as long — but nothing ever
/// drew one, so from inside the app there was no way to find out which
/// days they were. Reported as "it seems like i cant find the holiday
/// dates on calendar", which was exactly right.
void main() {
  // November 2026: Bonifacio Day falls on the 30th, a fixed date set by
  // law rather than one of the computed ones, so this test is about the
  // wiring and not about the arithmetic.
  final november = DateTime(2026, 11);

  Widget host({bool withHolidays = true}) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: MonthGrid(
        month: november,
        selected: DateTime(2026, 11, 19),
        onSelect: (_) {},
        holidayFor: withHolidays ? SchoolCalendar.holidayOn : null,
      ),
    ),
  );

  /// The grid wants a phone's height; the default test surface is
  /// short enough to overflow it, which has nothing to do with
  /// holidays.
  Future<void> pumpGrid(WidgetTester tester, {bool withHolidays = true}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(withHolidays: withHolidays));
    await tester.pump();
  }

  Color? colourOf(WidgetTester tester, String day) => tester
      .widget<Text>(
        find.descendant(of: find.byType(MonthGrid), matching: find.text(day)),
      )
      .style
      ?.color;

  test('the 30th of November is Bonifacio Day', () {
    expect(SchoolCalendar.holidayOn(DateTime(2026, 11, 30)), 'Bonifacio Day');
    expect(SchoolCalendar.holidayOn(DateTime(2026, 11, 19)), isNull);
  });

  testWidgets('a holiday is not drawn in the same ink as an ordinary day', (
    tester,
  ) async {
    await pumpGrid(tester);

    final holiday = colourOf(tester, '30');
    final ordinary = colourOf(tester, '26');
    expect(holiday, isNotNull);
    expect(
      holiday,
      isNot(ordinary),
      reason: 'the 30th is a holiday and reads exactly like the 26th',
    );
  });

  testWidgets('without the callback every day is drawn alike', (tester) async {
    // The grid is still a plain grid for the pickers that do not want
    // holidays marked, so the marking is the caller's choice.
    await pumpGrid(tester, withHolidays: false);

    expect(colourOf(tester, '30'), colourOf(tester, '26'));
  });

  testWidgets('a screen reader is told which holiday it is', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpGrid(tester);

    expect(
      find.bySemanticsLabel(RegExp('Bonifacio Day')),
      findsOneWidget,
      reason: 'the day says it is special but never says why',
    );
    handle.dispose();
  });
}
