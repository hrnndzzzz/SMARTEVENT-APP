import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smartevent/screens/home_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/state/sfx.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/theme/peso.dart';

/// The budget figure is covered until somebody asks for it.
///
/// Asked for because the dashboard is the screen most likely to be
/// open while a phone is lying on a table during an event, and the one
/// figure on it that is nobody else's business is how much money the
/// organisation has left.
void main() {
  Widget host(AppState app) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
      ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ChangeNotifierProvider(create: (_) => SfxPlayer()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(accent: app.themeColor),
      home: const HomeScreen(),
    ),
  );

  Future<AppState> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 2600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    addTearDown(app.dispose);
    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 400));
    return app;
  }

  testWidgets('it starts covered', (tester) async {
    final app = await open(tester);

    final figure = peso(app.remainingBalance, decimals: 0);
    expect(
      find.text(figure),
      findsNothing,
      reason: 'the balance was printed before anyone asked for it',
    );
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('the bar is covered too, not just the number', (tester) async {
    await open(tester);

    // The budget tile is the only one with a bar. A bar at four fifths
    // says roughly what is left on its own, so covering the figure and
    // leaving the bar would be theatre.
    final bars = tester.widgetList<BrutProgressBar>(
      find.byType(BrutProgressBar),
    );
    expect(
      bars,
      isEmpty,
      reason: 'the bar still drew the proportion the figure was hiding',
    );
  });

  testWidgets('the eye shows it, and the bar comes back', (tester) async {
    final app = await open(tester);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(peso(app.remainingBalance, decimals: 0)), findsOneWidget);
    expect(find.byType(BrutProgressBar), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('the long press does not hand the figure over', (tester) async {
    final app = await open(tester);

    // Covering the tile and then spelling the figure out on a hold
    // would be no protection at all.
    await tester.longPress(find.byIcon(Icons.visibility_off_outlined).first);
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.textContaining(peso(app.totalAllocated, decimals: 0)),
      findsNothing,
    );
  });

  test('a new launch starts covered again', () {
    final settings = AppSettings();
    expect(settings.balanceHidden, isTrue);
    settings.toggleBalanceHidden();
    expect(settings.balanceHidden, isFalse);
    // Not persisted on purpose: a setting that remembered "shown"
    // would be uncovered on the one occasion it mattered.
    expect(AppSettings().balanceHidden, isTrue);
  });
}
