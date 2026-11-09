import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/home_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';

/// The dashboard, as four figures and a bar.
///
/// It carried nine blocks: a hero card, four tiles, two stats, a
/// progress bar and a chart. Same complaint as the proposal form and
/// the event page — too much happening. Four squares now, one bar, then
/// the lists.
///
/// Holding a square shows what is behind it without going there, which
/// is the point of a dashboard: answering "should I go and look?".
void main() {
  Widget host(AppState app) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
      ChangeNotifierProvider(create: (_) => NoticeShelf()),
    ],
    child: const MaterialApp(home: Scaffold(body: HomeScreen())),
  );

  Future<AppState> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 2600);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo();
    await tester.pumpWidget(host(app));
    // Not pumpAndSettle: the bell rings on a repeating controller while
    // anything is unread, so nothing ever settles.
    await tester.pump(const Duration(milliseconds: 400));
    return app;
  }

  group('the four figures', () {
    testWidgets('all four are shown', (tester) async {
      await open(tester);

      expect(find.text('Events'), findsOneWidget);
      expect(find.text('Left to spend'), findsOneWidget);
      expect(find.text('Awaiting review'), findsOneWidget);
      expect(find.text('Low stock'), findsOneWidget);
    });

    testWidgets('and the blocks they replaced are gone', (tester) async {
      await open(tester);

      expect(
        find.text('Remaining budget'),
        findsNothing,
        reason: 'the hero card is what "too much happening" meant',
      );
      expect(find.text('Allocated'), findsNothing);
      expect(find.text('Approved spending'), findsNothing);
      expect(find.text('Flagged'), findsNothing);
      expect(find.text('Draft items'), findsNothing);
    });

    testWidgets('one bar is kept, because it is a proportion', (tester) async {
      await open(tester);

      // MonoLabel renders its text uppercased.
      expect(find.text('BUDGET USED'), findsOneWidget);
    });
  });

  group('the lists below', () {
    testWidgets('Your events survives, with the analytics after it', (
      tester,
    ) async {
      final app = await open(tester);

      // Exactly one: the module draws its own heading, and the
      // dashboard must not add a second above it.
      expect(find.text('Your events'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Your events')).dy,
        lessThan(tester.getTopLeft(find.text('Analytics')).dy),
      );
      expect(app.spendingTrends, isNotEmpty);
    });
  });

  group('holding a square', () {
    testWidgets('shows what is behind it without leaving the page', (
      tester,
    ) async {
      await open(tester);

      await tester.longPress(find.text('Awaiting review'));
      await tester.pump(const Duration(milliseconds: 400));

      // The sheet repeats the label as its title, so the name is now on
      // screen twice — the tile under it and the sheet over it.
      expect(find.text('Awaiting review'), findsNWidgets(2));
      expect(find.text('Open expenses'), findsOneWidget);
      expect(
        find.byType(HomeScreen),
        findsOneWidget,
        reason: 'a peek must not navigate away',
      );
    });

    testWidgets('the peek says something true about the figure', (
      tester,
    ) async {
      final app = await open(tester);

      await tester.longPress(find.text('Events'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining('${app.events.length} on record'),
        findsOneWidget,
      );
    });

    testWidgets('and a plain tap still opens the module', (tester) async {
      await open(tester);

      await tester.tap(find.text('Awaiting review'));
      // The route transition, then the pushed screen's own first load.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(find.text('Expenses'), findsWidgets);
    });
  });
}
