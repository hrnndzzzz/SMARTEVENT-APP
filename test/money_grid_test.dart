import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/screens/money_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/user_role.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// The four figures were one card split by hairlines, which gave the
/// same weight to context (what was allocated) and to a warning (how
/// little is left). Separate boxes now, each coloured by what it says.
void main() {
  test('green while there is room', () {
    expect(MoneyFigures.toneForUsed(0.0), BrutTone.mint);
    expect(MoneyFigures.toneForUsed(0.4), BrutTone.mint);
    expect(MoneyFigures.toneForUsed(0.69), BrutTone.mint);
  });

  test('amber as it tightens', () {
    expect(MoneyFigures.toneForUsed(0.7), BrutTone.sun);
    expect(MoneyFigures.toneForUsed(0.89), BrutTone.sun);
  });

  test('red when it is nearly gone', () {
    expect(MoneyFigures.toneForUsed(0.9), BrutTone.coral);
    expect(MoneyFigures.toneForUsed(1.0), BrutTone.coral);
  });

  test('the thresholds do not overlap or leave a gap', () {
    // Walk the whole range: every value must land somewhere, and the
    // colour must only ever get more urgent as it climbs.
    const order = {BrutTone.mint: 0, BrutTone.sun: 1, BrutTone.coral: 2};
    var previous = -1;

    for (var i = 0; i <= 100; i++) {
      final rank = order[MoneyFigures.toneForUsed(i / 100)];
      expect(rank, isNotNull, reason: 'nothing for ${i / 100}');
      expect(rank!, greaterThanOrEqualTo(previous), reason: 'went back at $i');
      previous = rank;
    }

    expect(previous, 2, reason: 'should end red');
  });

  group('it actually lays out', () {
    // The colour rule was unit-tested and the layout was not, so a Row
    // stretching its children inside a scrollable — where there is no
    // height to stretch to — shipped. The screen came up with the first
    // two figures and nothing else at all.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('all four figures are on the screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      final app = AppState()..enterDemo(role: UserRole.treasurer);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: MoneyFigures(app: app, onPending: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      for (final label in ['ALLOCATED', 'SPENT', 'LEFT', 'PENDING']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('and nothing overflows laying them out', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      final app = AppState()..enterDemo(role: UserRole.treasurer);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: MoneyFigures(app: app, onPending: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });
  });
}
