import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/income_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Membership dues belong to no event. The form offers the general fund
/// first, and then asks for the labels an event would otherwise supply.
void main() {
  testWidgets('the general fund asks for a school year and semester', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: UserRole.treasurer);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider(create: (_) => AppSettings()),
          ChangeNotifierProvider(create: (_) => Reachability()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const IncomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byType(FloatingActionButton));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('SEMESTER'), findsNothing);

    await tester.tap(find.text('Select an event or the general fund'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.text('General fund (no event)').last);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('SCHOOL YEAR'), findsOneWidget);
    expect(find.text('SEMESTER'), findsOneWidget);
    // Dues are the usual general-fund income, so the source follows.
    expect(find.text('Membership dues'), findsOneWidget);

    // Without a semester, nothing is recorded.
    final before = app.incomes.length;
    await tester.ensureVisible(find.text('Record income').last);
    await tester.tap(find.text('Record income').last);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Choose the semester'), findsOneWidget);
    expect(app.incomes.length, before);
    expect(tester.takeException(), isNull);
  });
}
