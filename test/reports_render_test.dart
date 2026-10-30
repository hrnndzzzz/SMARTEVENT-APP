import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/reports_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// The reports screen at the size of the phone it is demonstrated on.
///
/// Two bugs on this project rendered wrong only in release — the money
/// grid and the search result card both stretched a Row inside an
/// unbounded parent. A release build draws those silently wrong; a
/// debug pump asserts. So the screens are pumped at phone size and any
/// exception fails the test.
void main() {
  Widget host(AppState app) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
    ],
    child: const MaterialApp(home: ReportsScreen()),
  );

  testWidgets('reports lays out on a phone', (tester) async {
    // The A51 this is demonstrated on: 1080x2400 at 2.75.
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: UserRole.treasurer);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: host(app)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Charts'), findsOneWidget);
  });

  testWidgets('and the download sheet opens with all three formats', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: UserRole.treasurer);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: host(app)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byType(FloatingActionButton));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('PDF'), findsWidgets);
    expect(find.text('CSV'), findsWidgets);
    expect(find.text('Print-ready'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
