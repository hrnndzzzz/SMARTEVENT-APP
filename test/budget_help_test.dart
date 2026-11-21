import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/peso.dart';

/// Two things a tester asked for while filling in a budget.
///
/// "di pala sya pwede edit lang? ang option lang ay iclose yung X at
/// gumawa ulit bago" — a typo meant deleting the row and typing all
/// four fields again.
///
/// "wala kayo functions na habang nagtype ng budget makita ko na yung
/// available budget ng org?" — nothing said what was left, so there
/// was no way to tell you had gone over until somebody else said so.
void main() {
  SapForm formWith({String? budget}) {
    final form = SapForm(eventId: 'e1');
    form.updateDetails(
      (d) => d.copyWith(
        title: 'HACK THE FUTURE',
        activityDate: DateTime(2027, 1, 8),
        totalBudget: budget,
      ),
    );
    return form;
  }

  Future<AppState> pumpPart1(
    WidgetTester tester, {
    required SapForm form,
    bool withMoney = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 3400);
    addTearDown(tester.view.reset);

    final app = AppState();
    if (withMoney) app.enterDemo(role: UserRole.treasurer);
    addTearDown(app.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider(create: (_) => AppSettings()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SapPart1Screen(form: form),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return app;
  }

  group('what the organization has left', () {
    testWidgets('is shown under the budget, from figures already loaded', (
      tester,
    ) async {
      final app = await pumpPart1(tester, form: formWith());
      expect(app.categories, isNotEmpty, reason: 'the demo seeds no budget');

      expect(
        find.textContaining('${peso(app.remainingBalance)} left of'),
        findsOneWidget,
      );
    });

    testWidgets('asking for more than that says so, without refusing', (
      tester,
    ) async {
      final app = await pumpPart1(tester, form: formWith());
      final tooMuch = (app.remainingBalance + 50000).toStringAsFixed(2);

      await tester.enterText(
        find.widgetWithText(TextField, '2500.00'),
        tooMuch,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('That is more than the'), findsOneWidget);
      // Saved, not sent: the server refuses a budget over what is left.
      expect(
        find.textContaining('not sent until it fits'),
        findsOneWidget,
      );
    });

    testWidgets('an amount within it is left alone', (tester) async {
      final app = await pumpPart1(tester, form: formWith());

      await tester.enterText(
        find.widgetWithText(TextField, '2500.00'),
        (app.remainingBalance - 1).toStringAsFixed(2),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('That is more than the'), findsNothing);
    });

    testWidgets('says nothing at all when the figures are not loaded', (
      tester,
    ) async {
      // An unloaded category list and a genuinely empty budget look
      // identical from here, and a confident zero would be worse than
      // saying nothing.
      await pumpPart1(tester, form: formWith(), withMoney: false);

      expect(find.textContaining('left of'), findsNothing);
      expect(find.textContaining('That is more than the'), findsNothing);
    });
  });

  group('changing a budget line', () {
    test('a line replaces in place rather than being re-typed', () {
      // The screen's edit path is setBudgetItems with one index
      // swapped; this is the behaviour it relies on.
      final form = SapForm(eventId: 'e1');
      form.setBudgetItems(const [
        SapBudgetItem(particulars: 'Food', amount: '20.00'),
        SapBudgetItem(particulars: 'Guest speaker', amount: '2000.00'),
      ]);

      final fixed = [...form.budgetItems]
        ..[0] = const SapBudgetItem(
          particulars: 'Food',
          amount: '2000.00',
          quantity: 100,
          unitCost: '20.00',
        );
      form.setBudgetItems(fixed);

      expect(form.budgetItems, hasLength(2));
      expect(form.budgetItems[0].amount, '2000.00');
      expect(form.budgetItems[0].quantity, 100);
      // The line beside it is untouched, and the order is kept: a
      // delete-and-re-add sent the corrected row to the bottom.
      expect(form.budgetItems[1].particulars, 'Guest speaker');
    });
  });
}
