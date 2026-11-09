import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/home_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/widgets/event_progress_bar.dart';

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
      // The tile says what is left and what of, so the figure above it
      // needs no second line explaining itself.
      expect(find.textContaining('left'), findsWidgets);
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

    testWidgets('the budget bar is gone, the tile carries it instead', (
      tester,
    ) async {
      await open(tester);

      // MonoLabel renders its text uppercased.
      expect(
        find.text('BUDGET USED'),
        findsNothing,
        reason: 'the tile fills as the budget goes; a bar as well said '
            'the same thing twice',
      );
    });

    testWidgets('the next activity is above the figures', (tester) async {
      await open(tester);

      expect(
        tester.getTopLeft(find.text('NEXT UP')).dy,
        lessThan(tester.getTopLeft(find.text('Events')).dy),
        reason: 'it is the only thing here with a deadline attached',
      );
    });
  });

  group('the lists below', () {
    testWidgets('the events list is gone; the hold carries it', (
      tester,
    ) async {
      final app = await open(tester);

      expect(
        find.text('Your events'),
        findsNothing,
        reason: 'holding the Events tile shows all of them, and the '
            'Events tab is one tap away',
      );
      expect(find.text('Analytics'), findsOneWidget);
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

    testWidgets('the events peek shows the progress bars themselves', (
      tester,
    ) async {
      final app = await open(tester);

      await tester.longPress(find.text('Events'));
      await tester.pump(const Duration(milliseconds: 400));

      // Not a sentence about the events — the bars, one per live one.
      expect(find.byType(EventProgressPeek), findsOneWidget);
      final live = app.events
          .where((e) => e.status != EventApprovalStatus.completed)
          .length;
      // Scoped to the peek: the list below is still on screen behind
      // it, drawing its own three.
      expect(
        find.descendant(
          of: find.byType(EventProgressPeek),
          matching: find.byType(EventProgressBar),
        ),
        findsNWidgets(live),
        reason: 'the peek shows every live one, not the list\'s three',
      );
      expect(live, greaterThan(3), reason: 'otherwise this proves nothing');
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
