import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/inventory.dart';
import 'package:smartevent/state/app_state.dart';

/// Creating and maintaining the catalog, in the demo.
///
/// These are admin work, so the demo has to be switched to Admin before
/// the buttons appear at all — which is itself worth asserting, because
/// "the Add button is missing" turned out to be the role gate doing its
/// job rather than anything broken.
void main() {
  AppState admin() => AppState()..enterDemo(role: UserRole.admin);
  AppState treasurer() => AppState()..enterDemo(role: UserRole.treasurer);

  group('who may manage the catalog', () {
    test('a treasurer may not, so no Add button is offered', () {
      expect(treasurer().currentRole!.canManageCatalog, isFalse);
    });

    test('an admin may, and switching role in the demo grants it', () {
      final app = treasurer();
      expect(app.currentRole!.canManageCatalog, isFalse);

      app.switchDemoRole(UserRole.admin);

      expect(app.currentRole!.canManageCatalog, isTrue);
    });

    // canManageCatalog moved from isAdministrator to managesOrganization,
    // which takes in the adviser. Pinned so the next change to that rule
    // has to be deliberate.
    test('an adviser may too, within their own organization', () {
      final app = treasurer()..switchDemoRole(UserRole.adviser);

      expect(app.currentRole!.canManageCatalog, isTrue);
      expect(app.currentRole!.managesOrganization, isTrue);
    });

    test('an officer never may', () {
      final app = treasurer()..switchDemoRole(UserRole.officer);

      expect(app.currentRole!.canManageCatalog, isFalse);
    });
  });

  group('creating an item', () {
    test('it is added to the catalog', () async {
      final app = admin();
      await app.loadCatalog();
      final before = app.catalog.length;

      final error = await app.createInventoryItem(
        eventId: '',
        itemName: 'Folding chair',
        description: 'Stackable, grey',
        quantity: 24,
        unit: 'pcs',
        lowStockThreshold: 4,
        location: 'CITE stockroom',
      );

      expect(error, isNull, reason: 'the demo must not refuse this');
      expect(app.catalog.length, before + 1);
      expect(app.catalog.first.itemName, 'Folding chair');
      expect(app.catalog.first.quantity, 24);
    });

    test('its opening stock is on the ledger, not conjured onto the row', () async {
      final app = admin();
      await app.createInventoryItem(
        eventId: '',
        itemName: 'Folding chair',
        quantity: 24,
        unit: 'pcs',
        lowStockThreshold: 4,
        location: 'CITE stockroom',
      );
      final item = app.catalog.firstWhere((i) => i.itemName == 'Folding chair');

      final ledger = await app.loadMovements(item);

      expect(ledger.movements, hasLength(1));
      expect(ledger.movements!.single.changeQty, 24);
      expect(
        ledger.movements!.fold(0, (sum, m) => sum + m.changeQty),
        item.quantity,
        reason: 'the ledger must account for every unit on the row',
      );
    });

    test('an item created with no stock gets no phantom movement', () async {
      final app = admin();
      await app.createInventoryItem(
        eventId: '',
        itemName: 'Spare projector lamp',
        quantity: 0,
        unit: 'pcs',
        lowStockThreshold: 1,
        location: 'CITE stockroom',
      );
      final item =
          app.catalog.firstWhere((i) => i.itemName == 'Spare projector lamp');

      final ledger = await app.loadMovements(item);

      expect(ledger.movements, isEmpty);
    });

    test('a created item survives a filter', () async {
      final app = admin();
      await app.createInventoryItem(
        eventId: '',
        itemName: 'Folding chair',
        quantity: 24,
        unit: 'pcs',
        lowStockThreshold: 4,
        location: 'CITE stockroom',
      );

      await app.loadCatalog();

      expect(
        app.catalog.where((i) => i.itemName == 'Folding chair'),
        hasLength(1),
        reason: 'rebuilding from the seed would drop what was just created',
      );
    });
  });

  group('maintaining an item', () {
    test('editing metadata leaves the quantity alone', () async {
      final app = admin();
      await app.loadCatalog();
      final item = app.catalog.first;
      final quantity = item.quantity;

      final error = await app.updateInventoryItem(
        item,
        itemName: 'Renamed item',
        location: 'Moved to AVR',
      );

      expect(error, isNull, reason: 'the demo must not refuse this');
      final updated = app.catalog.firstWhere((i) => i.id == item.id);
      expect(updated.itemName, 'Renamed item');
      expect(updated.location, 'Moved to AVR');
      expect(
        updated.quantity,
        quantity,
        reason: 'only a movement may change stock',
      );
    });

    test('confirming a draft clears the draft flag without adding stock', () async {
      final app = admin();
      await app.loadCatalog();
      final draft = app.catalog.firstWhere((i) => i.isDraft);
      final quantity = draft.quantity;

      final error = await app.confirmInventoryDraft(draft);

      expect(error, isNull, reason: 'the demo must not refuse this');
      final confirmed = app.catalog.firstWhere((i) => i.id == draft.id);
      expect(confirmed.isDraft, isFalse);
      expect(confirmed.quantity, quantity);
    });

    test('deleting removes it and does not come back on a filter', () async {
      final app = admin();
      await app.loadCatalog();
      final item = app.catalog.first;

      final error = await app.deleteInventoryItem(item);

      expect(error, isNull, reason: 'the demo must not refuse this');
      expect(app.catalog.where((i) => i.id == item.id), isEmpty);
      await app.loadCatalog();
      expect(
        app.catalog.where((i) => i.id == item.id),
        isEmpty,
        reason: 'rebuilding from the seed would resurrect it',
      );
    });
  });

  group('categories', () {
    test('creating one starts with all of its budget remaining', () async {
      final app = admin();
      final before = app.categories.length;

      final error = await app.createCategory(
        name: 'Transport',
        allocatedBudget: 8000,
      );

      expect(error, isNull, reason: 'the demo must not refuse this');
      expect(app.categories.length, before + 1);
      final made = app.categories.firstWhere((c) => c.name == 'Transport');
      expect(made.allocatedBudget, 8000);
      expect(made.remainingBudget, 8000);
    });

    test('raising the allocation does not top up what is left', () async {
      final app = admin();
      final category = app.categories.first;
      final remaining = category.remainingBudget;

      await app.updateCategory(
        category,
        allocatedBudget: category.allocatedBudget + 5000,
      );

      final updated =
          app.categories.firstWhere((c) => c.id == category.id);
      expect(updated.allocatedBudget, category.allocatedBudget + 5000);
      expect(
        updated.remainingBudget,
        remaining,
        reason: 'remaining only moves when money is spent',
      );
    });

    test('a category still in use cannot be deleted', () async {
      final app = admin();
      final used = app.categories
          .firstWhere((c) => app.expenses.any((e) => e.category == c.name));

      final error = await app.deleteCategory(used);

      expect(error, isNotNull, reason: 'the backend refuses this too');
      expect(error, contains('still reference'));
      expect(app.categories, contains(used));
    });

    test('an unused category deletes cleanly', () async {
      final app = admin();
      await app.createCategory(name: 'Transport', allocatedBudget: 8000);
      final made = app.categories.firstWhere((c) => c.name == 'Transport');

      final error = await app.deleteCategory(made);

      expect(error, isNull);
      expect(app.categories.where((c) => c.name == 'Transport'), isEmpty);
    });

    test('setting a budget creates one, then updates the same one', () async {
      final app = admin();
      final before = app.categories.length;

      await app.setCategoryBudget('Transport', 8000);
      expect(app.categories.length, before + 1);

      await app.setCategoryBudget('Transport', 9500);

      expect(
        app.categories.length,
        before + 1,
        reason: 'the second call must not create a duplicate',
      );
      expect(
        app.categories.firstWhere((c) => c.name == 'Transport').allocatedBudget,
        9500,
      );
    });
  });
}
