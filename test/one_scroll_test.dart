import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/categories_screen.dart';
import 'package:smartevent/screens/events_screen.dart';
import 'package:smartevent/screens/income_screen.dart';
import 'package:smartevent/screens/proposal_letters_screen.dart';
import 'package:smartevent/screens/inventory_screen.dart';
import 'package:smartevent/screens/receipts_screen.dart';
import 'package:smartevent/screens/risk_screen.dart';
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
  Widget host(AppState app, [Widget screen = const InventoryScreen()]) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider(create: (_) => AppSettings()),
          ChangeNotifierProvider(create: (_) => Reachability()),
          ChangeNotifierProvider(create: (_) => NoticeShelf()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(accent: app.themeColor),
          home: screen,
        ),
      );

  Future<AppState> open(
    WidgetTester tester, [
    Widget screen = const InventoryScreen(),
  ]) async {
    await tester.binding.setSurfaceSize(const Size(411, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppState()..enterDemo();
    addTearDown(app.dispose);
    await tester.pumpWidget(host(app, screen));
    await tester.pump(const Duration(milliseconds: 400));
    return app;
  }

  /// Vertically scrolling widgets on screen, not counting the ones
  /// inside text fields.
  ///
  /// Two exclusions, both deliberate. Horizontal scrollers are fine: a
  /// chip bar running off the edge is a row of filters, not a second
  /// page. And every `EditableText` carries a vertical Scrollable of
  /// its own for long input — a screen with a search box and two
  /// filters was reporting four scrollers and none of them was the
  /// letterbox.
  int verticalScrollers(WidgetTester tester) {
    var count = 0;
    for (final element in find.byType(Scrollable).evaluate()) {
      if ((element.widget as Scrollable).axisDirection != AxisDirection.down) {
        continue;
      }
      var insideAField = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is EditableText) {
          insideAField = true;
          return false;
        }
        return true;
      });
      if (!insideAField) count++;
    }
    return count;
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

    expect(
      verticalScrollers(tester),
      1,
      reason: 'a vertical scroll inside a vertical scroll is the letterbox',
    );
  });

  group('every module screen built the same way', () {
    // Eight screens carried `scrollable: false` and a top-level
    // Expanded. These seven are converted; the invariant is checked per
    // screen so the next one to be rebuilt as two halves is caught
    // here rather than on somebody's phone.
    //
    // Admin is the one left out, and on purpose: each of its three tabs
    // keeps its floating buttons in a Positioned inside the scroller,
    // so making the page scroll as one would send the primary actions
    // down the page with it. That is a different change from a scroll
    // fix and wants doing deliberately.
    const screens = <String, Widget>{
      'Inventory': InventoryScreen(),
      'Flagged': RiskScreen(),
      'Income': IncomeScreen(),
      'Receipts': ReceiptsScreen(),
      'Categories': CategoriesScreen(),
      'Proposal letters': ProposalLettersScreen(),
      'Events': EventsScreen(),
    };

    screens.forEach((name, screen) {
      testWidgets('$name scrolls as one page', (tester) async {
        await open(tester, screen);
        expect(
          verticalScrollers(tester),
          1,
          reason: '$name has a scroll inside a scroll',
        );
      });
    });
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
