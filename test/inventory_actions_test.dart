import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/inventory_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';

/// Adding an item and moving stock are two permissions, and the screen
/// used to offer neither to a treasurer: "New item" is adviser and above,
/// and "Record movement" lived only inside an item's own page. So a
/// treasurer opened Inventory, saw a list, and had no way to act on it.
void main() {
  Widget host(AppState app) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
      ChangeNotifierProvider(create: (_) => NoticeShelf()),
    ],
    child: const MaterialApp(home: InventoryScreen()),
  );

  Future<void> open(WidgetTester tester, UserRole role) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 1600);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: role);
    await app.loadCatalog();
    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 300));
  }

  // BrutIconButton publishes its label as a semantics label, not a
  // tooltip — byTooltip matched nothing at all, which made the negative
  // cases pass without proving anything.
  Finder moveButtons() => find.bySemanticsLabel(RegExp('Record a movement'));

  group('moving stock', () {
    testWidgets('a treasurer can move stock from the list itself', (
      tester,
    ) async {
      await open(tester, UserRole.treasurer);

      expect(
        moveButtons(),
        findsWidgets,
        reason: 'this is the errand the screen exists for',
      );
    });

    testWidgets('an adviser can too', (tester) async {
      await open(tester, UserRole.adviser);

      expect(moveButtons(), findsWidgets);
    });

    testWidgets('a signatory cannot', (tester) async {
      await open(tester, UserRole.signatory);

      expect(moveButtons(), findsNothing);
    });

    testWidgets('a draft offers no movement until it is confirmed', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 1600);
      addTearDown(tester.view.reset);

      final app = AppState()..enterDemo(role: UserRole.treasurer);
      await app.applyCatalogFilter(isDraft: true);
      await tester.pumpWidget(host(app));
      await tester.pump(const Duration(milliseconds: 300));

      expect(app.catalog, isNotEmpty, reason: 'the demo seeds one draft');
      expect(app.catalog.every((i) => !i.isUsable), isTrue);
      expect(
        moveButtons(),
        findsNothing,
        reason: 'a draft has no event to move stock against',
      );
    });
  });

  group('adding an item', () {
    testWidgets('an adviser is offered it', (tester) async {
      await open(tester, UserRole.adviser);

      expect(find.text('New item'), findsOneWidget);
    });

    testWidgets('a treasurer is not, and is told whose job it is', (
      tester,
    ) async {
      await open(tester, UserRole.treasurer);

      expect(find.text('New item'), findsNothing);
      expect(
        find.textContaining('adviser or administrator'),
        findsOneWidget,
        reason: 'an absent button reads as a broken screen unless it is '
            'explained',
      );
    });
  });
}
