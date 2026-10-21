import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// An activity needs a month's notice. The server only holds off-campus
/// activities to it, and only at submission — too late to be any use to
/// someone who has already filled in three parts. Part 1 says so on the
/// date itself and will not go on until it is fixed.
Widget host(Widget child) =>
    MaterialApp(theme: AppTheme.light(), home: child);

SapForm formDated(DateTime activity, {DateTime? proposed}) {
  final form = SapForm(eventId: 'e1');
  form.updateDetails(
    (d) => d.copyWith(
      activityDate: activity,
      proposalDate: proposed ?? DateTime(2026, 1, 1),
    ),
  );
  return form;
}

void main() {
  testWidgets('a date inside the month is refused on the spot', (tester) async {
    // 10 days out.
    await tester.pumpWidget(
      host(SapPart1Screen(form: formDated(DateTime(2026, 1, 11)))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('30 days of notice'), findsOneWidget);
    expect(find.textContaining('10 days away'), findsOneWidget);
  });

  testWidgets('the step will not advance while it is too soon', (tester) async {
    await tester.pumpWidget(
      host(SapPart1Screen(form: formDated(DateTime(2026, 1, 11)))),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<BrutButton>(
      find.widgetWithText(BrutButton, 'Save'),
    );
    expect(button.onPressed, isNull, reason: 'too soon to go on');
  });

  testWidgets('a month and a day out is accepted', (tester) async {
    await tester.pumpWidget(
      host(SapPart1Screen(form: formDated(DateTime(2026, 2, 1)))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('30 days of notice'), findsNothing);
  });

  testWidgets('exactly thirty days is enough', (tester) async {
    await tester.pumpWidget(
      host(SapPart1Screen(form: formDated(DateTime(2026, 1, 31)))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('30 days of notice'), findsNothing);
  });

  testWidgets('a date already gone says so plainly', (tester) async {
    await tester.pumpWidget(
      host(SapPart1Screen(form: formDated(DateTime(2025, 12, 20)))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('already passed'), findsOneWidget);
  });

  testWidgets('no activity date yet means nothing to complain about', (
    tester,
  ) async {
    await tester.pumpWidget(host(SapPart1Screen(form: SapForm(eventId: 'e1'))));
    await tester.pumpAndSettle();

    expect(find.textContaining('30 days of notice'), findsNothing);
    expect(find.textContaining('already passed'), findsNothing);
  });
}
