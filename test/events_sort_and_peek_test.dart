import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/events_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/widgets/event_progress_bar.dart';
import 'package:smartevent/widgets/floating_peek.dart';

/// Ordering the list, and looking at a row without opening it.
void main() {
  Widget host(AppState app) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
      ChangeNotifierProvider(create: (_) => NoticeShelf()),
    ],
    child: const MaterialApp(home: EventsScreen()),
  );

  Future<AppState> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 2600);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo();
    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 400));
    return app;
  }

  /// The titles on screen, top to bottom.
  List<String> order(WidgetTester tester, AppState app) {
    final titles = app.events.map((e) => e.title).toSet();
    final seen = <(double, String)>[];
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      final text = w.data;
      if (text == null || !titles.contains(text)) continue;
      final box = tester.renderObject<RenderBox>(find.text(text).first);
      seen.add((box.localToGlobal(Offset.zero).dy, text));
    }
    seen.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, title) in seen) title];
  }

  group('sorting', () {
    testWidgets('the list opens soonest first', (tester) async {
      final app = await open(tester);

      final dated = [
        for (final e in app.events)
          if (e.on != null) e,
      ]..sort((a, b) => a.on!.compareTo(b.on!));
      final shown = order(tester, app);

      expect(
        shown.indexOf(dated.first.title),
        lessThan(shown.indexOf(dated.last.title)),
        reason: 'the list is read to find out what is coming',
      );
    });

    testWidgets('the control offers every order', (tester) async {
      await open(tester);

      await tester.tap(find.bySemanticsLabel(RegExp('Sort events')));
      await tester.pump(const Duration(milliseconds: 400));

      // Twice for the one in force: once as the panel's subtitle,
      // saying what the order is now, and once as a choice.
      expect(find.text('Soonest first'), findsNWidgets(2));
      expect(find.text('Latest first'), findsOneWidget);
      expect(find.text('By name'), findsOneWidget);
      expect(find.text('By status'), findsOneWidget);
    });

    testWidgets('choosing by name reorders the list', (tester) async {
      final app = await open(tester);

      await tester.tap(find.bySemanticsLabel(RegExp('Sort events')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('By name'));
      await tester.pump(const Duration(milliseconds: 400));

      final shown = order(tester, app);
      final alphabetical = [...shown]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      expect(shown, alphabetical);
    });

    testWidgets('and latest first is the reverse of soonest', (tester) async {
      final app = await open(tester);
      final soonest = order(tester, app);

      await tester.tap(find.bySemanticsLabel(RegExp('Sort events')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Latest first'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(order(tester, app), soonest.reversed.toList());
    });
  });

  group('holding a row', () {
    testWidgets('shows where that one has got to', (tester) async {
      final app = await open(tester);
      final first = order(tester, app).first;

      await tester.longPress(find.text(first).first);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(EventProgressPeek), findsOneWidget);
      expect(find.text('Open this event'), findsOneWidget);
      expect(
        find.byType(EventsScreen),
        findsOneWidget,
        reason: 'a peek must not navigate away',
      );
    });

    testWidgets('and it floats rather than rising from the bottom', (
      tester,
    ) async {
      final app = await open(tester);
      final first = order(tester, app).first;

      await tester.longPress(find.text(first).first);
      await tester.pump(const Duration(milliseconds: 400));

      // Centred, not docked: the panel's middle sits near the screen's,
      // which a bottom sheet never does.
      final panel = tester.getRect(find.byType(EventProgressPeek));
      final screen = tester.getSize(find.byType(EventsScreen));
      expect(panel.center.dy, lessThan(screen.height * 0.75));
    });
  });
}
