import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smartevent/screens/inventory_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/state/sfx.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// Finding one thing in the catalogue.
///
/// Asked for as "lets do the same on inventory, but lets add a search
/// bar and a button to find all the list of inventory storages and
/// location". Until now the only way to learn which shelves existed was
/// to scroll the whole list and read the headings.
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
      home: const InventoryScreen(),
    ),
  );

  /// A sheet or a peek slides in. One 400ms pump leaves it still
  /// below the bottom of the screen, where a tap lands on nothing and
  /// the test reads as a broken filter rather than a short wait.
  Future<void> settlePanel(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<AppState> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 3000);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo(role: UserRole.officer);
    addTearDown(app.dispose);
    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 400));
    return app;
  }

  testWidgets('the search narrows the list to what was typed', (tester) async {
    final app = await open(tester);
    final names = app.catalog.map((i) => i.itemName).toList();
    expect(names.length, greaterThan(1), reason: 'the demo has one item');

    final wanted = names.firstWhere((n) => n.toLowerCase().contains('micro'));
    final other = names.firstWhere((n) => n != wanted);

    await tester.enterText(find.byType(TextField).first, 'micro');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(wanted), findsOneWidget);
    expect(
      find.text(other),
      findsNothing,
      reason: 'the search matched but did not filter',
    );
  });

  testWidgets('a search that matches nothing says what it searched for', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(find.byType(TextField).first, 'xyzzy');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('xyzzy'), findsWidgets);
  });

  testWidgets('the places button lists every storage place with a count', (
    tester,
  ) async {
    final app = await open(tester);
    final places = app.catalog
        .map((i) => i.location?.trim())
        .whereType<String>()
        .where((l) => l.isNotEmpty)
        .toSet();
    expect(places.length, greaterThan(1), reason: 'the demo has one place');

    await tester.tap(find.text('Places'));
    await settlePanel(tester);

    expect(find.text('Storage places'), findsOneWidget);
    for (final place in places) {
      expect(find.text(place), findsWidgets, reason: '$place was not listed');
    }
    // The way back out, so choosing a shelf is not a one-way door.
    expect(find.text('Everywhere'), findsOneWidget);
  });

  testWidgets('choosing a place filters to it and the button says so', (
    tester,
  ) async {
    final app = await open(tester);
    final place = app.catalog
        .map((i) => i.location?.trim())
        .whereType<String>()
        .firstWhere((l) => l.isNotEmpty);
    final elsewhere = app.catalog
        .firstWhere((i) => (i.location?.trim() ?? '') != place)
        .itemName;

    await tester.tap(find.text('Places'));
    await settlePanel(tester);
    // Scoped to the sheet: the same name is a heading in the list
    // behind it, and tapping that does nothing.
    await tester.tap(
      find.descendant(of: find.byType(BrutSheet), matching: find.text(place)),
    );
    await settlePanel(tester);

    expect(find.text(elsewhere), findsNothing);
    expect(
      find.text(place),
      findsWidgets,
      reason: 'the button no longer says which place is in force',
    );
  });

  testWidgets('sorting by name drops the location headings', (tester) async {
    await open(tester);

    expect(find.text('By place'), findsOneWidget);
    await tester.tap(find.text('By place'));
    await settlePanel(tester);
    await tester.tap(find.text('Name A–Z').last);
    await settlePanel(tester);

    // An A–Z list printed under five shelf headings is five A–Z lists,
    // which is not what was asked for.
    expect(find.text('AV cabinet'), findsNothing);
    expect(find.text('Name A–Z'), findsOneWidget);
  });
}
