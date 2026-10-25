import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/inventory_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/state/app_state.dart';

/// The demo is what gets shown at a defence, and the Inventory screen
/// was empty in it: nothing was seeded, so "No items yet" was all anyone
/// ever saw — on the module the moderator asked about by name.
void main() {
  test('the demo holds equipment', () {
    final app = AppState()..enterDemo(role: UserRole.treasurer);

    expect(app.catalog, isNotEmpty);
  });

  test('every stock filter has something to find', () {
    final app = AppState()..enterDemo(role: UserRole.treasurer);

    expect(
      app.catalog.where((i) => i.quantity == 0),
      isNotEmpty,
      reason: 'None left',
    );
    expect(
      app.catalog.where((i) => i.quantity > 0 && i.quantity <= i.lowStockThreshold),
      isNotEmpty,
      reason: 'Low stock',
    );
    expect(
      app.catalog.where((i) => i.quantity > i.lowStockThreshold),
      isNotEmpty,
      reason: 'Available',
    );
  });

  test('some equipment is linked to an event and some is not', () {
    // The link is what the moderator asked about, so the demo has to
    // show both sides of it.
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final ids = {for (final e in app.events) e.remoteId};

    final linked = app.catalog.where((i) => i.eventId != null);
    expect(linked, isNotEmpty);
    expect(
      linked.every((i) => ids.contains(i.eventId)),
      isTrue,
      reason: 'a link to an event the demo does not have is worse than none',
    );
    expect(app.catalog.where((i) => i.eventId == null), isNotEmpty);
  });

  group('an empty shelf is not a low one', () {
    // The "Low stock" filter excludes zero (quantity > 0 && isLowStock)
    // but the badge used isLowStock alone, which is true at zero — so a
    // row read "Low stock" while the filter above it counted it under
    // "None left".
    testWidgets('zero reads as none left, not low stock', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2600);
      addTearDown(tester.view.reset);

      final app = AppState()..enterDemo(role: UserRole.treasurer);
      final empty = app.catalog.firstWhere((i) => i.quantity == 0);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: app),
            ChangeNotifierProvider(create: (_) => AppSettings()),
            ChangeNotifierProvider(create: (_) => Reachability()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const InventoryScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(empty.itemName), findsOneWidget);
      expect(find.text('None left'), findsWidgets);
      expect(
        find.text('Low stock (\u2264 ${empty.lowStockThreshold})'),
        findsNothing,
        reason: 'the filter does not call zero low, so neither should the row',
      );
    });
  });
}
