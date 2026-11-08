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

  group('adding or deducting stock', () {
    // A route's animation starts on the frame after the tap, so one frame
    // to start it and one to finish it.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    int projected(WidgetTester tester) {
      final text = tester
          .widget<Text>(find.textContaining('Stock would become'))
          .data!;
      return int.parse(RegExp(r'become (-?\d+)').firstMatch(text)!.group(1)!);
    }

    testWidgets('the sheet adds by default, and Deduct takes the same count away', (
      tester,
    ) async {
      await open(tester, UserRole.officer);
      await tester.tap(moveButtons().first);
      await settle(tester);

      expect(find.text('Add stock'), findsOneWidget);
      expect(find.text('Bought or acquired'), findsOneWidget);
      final added = projected(tester);

      await tester.tap(find.text('Deduct stock'));
      await settle(tester);
      expect(find.text('Issued for an event'), findsOneWidget);
      expect(added - projected(tester), 2, reason: '+1 became -1');

      // A correction takes its direction from the chip, not a typed minus.
      await tester.tap(find.text('Issued for an event'));
      await settle(tester);
      await tester.tap(find.text('Adjustment').last);
      await settle(tester);
      expect(added - projected(tester), 2);
    });
  });

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
