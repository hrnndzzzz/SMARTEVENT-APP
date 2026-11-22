import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartevent/theme/app_colors.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/widgets/brut_amount_field.dart';

/// A chip is as wide as its word.
///
/// Found on a handset: the +₱500 and +₱1,000 steps under an amount sat
/// one per line instead of side by side. `BrutSurface` is a Container,
/// and a Container given an alignment grows to fill the width it is
/// offered. The row of filters on the events screen scrolls, so its
/// chips were measured against unbounded width and shrank anyway — which
/// is why nobody saw this until a chip was put in a Wrap.
void main() {
  Widget host(Widget child, {double width = 400}) => MaterialApp(
    theme: AppTheme.light(accent: AppColors.brand),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );

  testWidgets('two chips in a Wrap share one line', (tester) async {
    await tester.pumpWidget(
      host(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            BrutChip(label: '+₱500', selected: false, onTap: () {}),
            BrutChip(label: '+₱1,000', selected: false, onTap: () {}),
          ],
        ),
      ),
    );

    final first = tester.getRect(find.text('+₱500'));
    final second = tester.getRect(find.text('+₱1,000'));
    expect(
      first.top,
      second.top,
      reason: 'the chips wrapped onto separate lines, so one is full width',
    );
    expect(
      first.right,
      lessThan(second.left),
      reason: 'the chips should sit side by side, in order',
    );
  });

  testWidgets('a chip is no wider than its label needs', (tester) async {
    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.centerLeft,
          child: BrutChip(label: 'Yes', selected: false, onTap: () {}),
        ),
      ),
    );

    // Generous, because the padding and the border are real: the point
    // is that it is nothing like the 400 it was offered.
    expect(tester.getSize(find.byType(BrutChip)).width, lessThan(120));
  });

  testWidgets('the step chips under an amount sit on one line', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        BrutAmountField(
          controller: controller,
          label: 'Amount',
          hint: '2000.00',
        ),
      ),
    );

    // The first step is the +/- increment; the rest become chips.
    final five = tester.getRect(find.text('+₱500'));
    final thousand = tester.getRect(find.text('+₱1,000'));
    expect(
      five.top,
      thousand.top,
      reason: 'the amount steps are stacked again, a line each',
    );
  });
}
