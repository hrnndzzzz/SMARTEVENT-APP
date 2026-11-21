import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/widgets/brut_amount_field.dart';

/// The amount, with the figure given the room it deserves.
///
/// Asked for with a reference image: a minus, the value and a plus
/// across the card. The field stays a field — a stepper alone cannot
/// say 2,347.50, and pressing plus twenty-three times is worse than
/// what it replaced.
void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  Future<void> pump(
    WidgetTester tester, {
    List<int> steps = const [100, 500, 1000],
    bool enabled = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: BrutAmountField(
              controller: controller,
              steps: steps,
              enabled: enabled,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tapLabel(WidgetTester tester, String label) async {
    await tester.tap(find.bySemanticsLabel(label));
    await tester.pump();
  }

  testWidgets('plus adds the first step, from nothing', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    await tapLabel(tester, 'Add ₱100');
    expect(controller.text, '100.00');

    await tapLabel(tester, 'Add ₱100');
    expect(controller.text, '200.00');
    handle.dispose();
  });

  testWidgets('minus takes it off, and never goes below zero', (tester) async {
    final handle = tester.ensureSemantics();
    controller.text = '150.00';
    await pump(tester);

    await tapLabel(tester, 'Take off ₱100');
    expect(controller.text, '50.00');

    // An amount owed is not an amount. The field it feeds refuses a
    // negative anyway, so the control must not produce one.
    await tapLabel(tester, 'Take off ₱100');
    expect(controller.text, '0.00');
    handle.dispose();
  });

  testWidgets('minus at zero writes nothing at all', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(controller.text, isEmpty);

    await tapLabel(tester, 'Take off \u20b1100');

    // Not "0.00": an empty amount and a zero amount are different
    // answers, and pressing minus on an empty field is not a claim
    // that the amount is zero.
    expect(controller.text, isEmpty);
    handle.dispose();
  });

  testWidgets('the larger steps are offered as chips', (tester) async {
    await pump(tester);

    expect(find.text('+₱500'), findsOneWidget);
    expect(find.text('+₱1,000'), findsOneWidget);
    // The first step is the minus and plus, so it is not repeated.
    expect(find.text('+₱100'), findsNothing);

    await tester.tap(find.text('+₱500'));
    await tester.pump();
    expect(controller.text, '500.00');
  });

  testWidgets('Clear appears only once there is something to clear', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Clear'), findsNothing);

    await tester.tap(find.text('+₱500'));
    await tester.pump();
    expect(find.text('Clear'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('typing is left exactly as typed', (tester) async {
    await pump(tester);

    // The SAP breakdown compares its decimal against the server's
    // character for character, so nothing may reformat it.
    await tester.enterText(find.byType(TextField), '2347.5');
    await tester.pump();
    expect(controller.text, '2347.5');
  });

  testWidgets('it spells out what the figure comes to', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '25000');
    await tester.pump();

    // A long number typed without separators is easy to get wrong by
    // a factor of ten, and this is the screen that costs money.
    expect(find.text('₱25,000.00'), findsOneWidget);
  });

  testWidgets('disabled offers no buttons at all', (tester) async {
    controller.text = '500';
    await pump(tester, enabled: false);

    expect(find.text('+₱500'), findsNothing);
    expect(find.text('Clear'), findsNothing);
  });
}
