import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/inventory_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/widgets/module_band.dart';

/// A module screen scrolls as one page.
///
/// It used to be two halves. The coloured band, the last-change note,
/// four figures, a line of prose and two rows of filters came to about
/// half a phone and none of it moved; the catalogue scrolled inside
/// whatever was left. So the list was read through a letterbox, and
/// pulling down on the fixed half did nothing at all.
///
/// Reported from a phone, with a screenshot: "pwede ba kapag nag scroll
/// up, nag-scroll up din lahat — para hindi yung half lang yung
/// nakikita?"
void main() {
  Widget host(AppState app) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
      ChangeNotifierProvider(create: (_) => NoticeShelf()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(accent: app.themeColor),
      home: const InventoryScreen(),
    ),
  );

  Future<AppState> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(411, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppState()..enterDemo();
    addTearDown(app.dispose);
    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 400));
    return app;
  }

  testWidgets('the band scrolls away with everything else', (tester) async {
    await open(tester);

    final before = tester.getRect(find.byType(ModuleBand)).top;

    // Dragged from low on the page, over the list — the gesture a
    // thumb actually makes. Before this, the band did not care.
    await tester.drag(find.byType(InventoryScreen), const Offset(0, -260));
    // Timed pumps, not pumpAndSettle: the header's bell and the menu's
    // waiting counts breathe on a repeating timer, so nothing on this
    // screen is ever "settled".
    await tester.pump(const Duration(milliseconds: 400));

    final after = tester.getRect(find.byType(ModuleBand)).top;
    expect(
      after,
      lessThan(before - 100),
      reason: 'the band stayed put while the list moved under it',
    );
  });

  testWidgets('and the list is not a second scroller inside the first', (
    tester,
  ) async {
    await open(tester);

    // Horizontal ones are allowed: a chip bar that runs off the edge
    // is a row of filters, not a second page. What must not exist is a
    // second vertical scroll, because that is the letterbox.
    final vertical = tester
        .widgetList<Scrollable>(find.byType(Scrollable))
        .where((s) => s.axisDirection == AxisDirection.down)
        .length;
    expect(
      vertical,
      1,
      reason: 'a vertical scroll inside a vertical scroll is the letterbox',
    );
  });

  testWidgets('the whole page is still pullable to refresh', (tester) async {
    await open(tester);

    // The list used to own the gesture, so pulling on the fixed top
    // half did nothing — which is the half you are looking at when a
    // figure seems stale.
    expect(find.byType(RefreshIndicator), findsOneWidget);
    final band = tester.getRect(find.byType(ModuleBand));
    await tester.dragFrom(band.center, const Offset(0, 300));
    await tester.pump();
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
