import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// The analytics figures count up from zero.
///
/// Asked for as "analytics should have an animation of starting from
/// zero to the point of the percentage shown". The point of it is that
/// 60% arrives having passed 30%, so the figure lands on a scale
/// instead of simply being there.
void main() {
  Widget host({double? countTo, String Function(double)? format}) =>
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: BrutMetricTile(
            label: 'Budget used',
            value: '60%',
            countTo: countTo,
            format: format,
          ),
        ),
      );

  String? figure(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .firstWhere((d) => d != null && d.endsWith('%'), orElse: () => null);

  testWidgets('it starts at zero and finishes on the real figure', (
    tester,
  ) async {
    await tester.pumpWidget(host(countTo: 60, format: (t) => '${t.round()}%'));

    expect(figure(tester), '0%', reason: 'it did not start from zero');

    // Part way through it is somewhere in between, which is the whole
    // point — a tile that jumps from 0% to 60% has animated nothing.
    await tester.pump(const Duration(milliseconds: 300));
    final middle = int.parse(figure(tester)!.replaceAll('%', ''));
    expect(middle, greaterThan(0));
    expect(middle, lessThan(60));

    await tester.pump(const Duration(milliseconds: 900));
    expect(figure(tester), '60%', reason: 'it never arrived');
  });

  testWidgets('without a count it prints the value straight away', (
    tester,
  ) async {
    // Budget used is an em dash when there is no approved budget, and
    // an em dash cannot be interpolated.
    await tester.pumpWidget(host());
    expect(figure(tester), '60%');
  });

  testWidgets('reduced motion gets the figure, not the animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: host(countTo: 60, format: (t) => '${t.round()}%'),
      ),
    );

    expect(
      figure(tester),
      '60%',
      reason: 'a phone asking for less motion was made to watch a count',
    );
  });
}
