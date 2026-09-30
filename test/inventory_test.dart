import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/inventory.dart';

/// Stock direction is the dangerous part of this module: a sign error moves
/// inventory the wrong way and the ledger then lies about what happened.
///
/// Forms ask for a positive count and derive the sign from what happened,
/// so these cover that derivation.
RemoteInventoryItem _item({
  int quantity = 10,
  int threshold = 5,
  bool isDraft = false,
  String? eventId = 'e1',
}) {
  return RemoteInventoryItem.fromJson({
    'id': 'i1',
    'item_name': 'Folding chairs',
    'description': null,
    'quantity': quantity,
    'unit': 'pcs',
    'low_stock_threshold': threshold,
    'location': 'Storeroom',
    'is_draft': isDraft,
    'event_id': eventId,
    'department_id': 'd1',
    'organization_id': 'o1',
    'created_at': '2026-09-20T10:00:00Z',
    'updated_at': '2026-09-20T10:00:00Z',
  });
}

void main() {
  group('movement direction', () {
    test('incoming types force a positive change', () {
      for (final type in [
        InventoryMovementType.acquisition,
        InventoryMovementType.donation,
        InventoryMovementType.returned,
      ]) {
        expect(signedChangeFor(type, '5'), 5, reason: type.name);
        // Even if a user types a minus, an arrival is an arrival.
        expect(signedChangeFor(type, '-5'), 5, reason: '${type.name} negated');
      }
    });

    test('outgoing types force a negative change', () {
      for (final type in [
        InventoryMovementType.issue,
        InventoryMovementType.disposal,
      ]) {
        // The user types "5" meaning "issue five", not "-5".
        expect(signedChangeFor(type, '5'), -5, reason: type.name);
        expect(signedChangeFor(type, '-5'), -5, reason: '${type.name} negated');
      }
    });

    test('an adjustment respects the sign the user chose', () {
      // The only case where direction is genuinely the user's decision.
      expect(signedChangeFor(InventoryMovementType.adjustment, '5'), 5);
      expect(signedChangeFor(InventoryMovementType.adjustment, '-5'), -5);
    });

    test('zero and junk are refused', () {
      for (final type in selectableMovementTypes) {
        expect(signedChangeFor(type, '0'), isNull, reason: type.name);
        expect(signedChangeFor(type, ''), isNull, reason: type.name);
        expect(signedChangeFor(type, 'five'), isNull, reason: type.name);
        expect(signedChangeFor(type, '2.5'), isNull,
            reason: 'stock is whole units');
      }
    });

    test('surrounding whitespace is tolerated', () {
      expect(signedChangeFor(InventoryMovementType.issue, '  3  '), -3);
    });
  });

  group('which types a user may pick', () {
    test('purchase is not selectable — it comes from completing an expense',
        () {
      expect(selectableMovementTypes,
          isNot(contains(InventoryMovementType.purchase)));
      expect(InventoryMovementType.purchase.isUserSelectable, isFalse);
    });

    test('opening balance and legacy are states, not actions', () {
      expect(selectableMovementTypes,
          isNot(contains(InventoryMovementType.openingBalance)));
      expect(selectableMovementTypes,
          isNot(contains(InventoryMovementType.legacy)));
    });

    test('the six real actions are offered', () {
      expect(selectableMovementTypes, containsAll([
        InventoryMovementType.acquisition,
        InventoryMovementType.donation,
        InventoryMovementType.issue,
        InventoryMovementType.returned,
        InventoryMovementType.disposal,
        InventoryMovementType.adjustment,
      ]));
      expect(selectableMovementTypes.length, 6);
    });
  });

  group('wire values', () {
    test('round-trips every movement type', () {
      for (final type in InventoryMovementType.values) {
        expect(inventoryMovementTypeFromWire(type.wireName), type);
      }
    });

    test('return is sent as "return", not the Dart enum name', () {
      // The Dart name is `returned` because `return` is a keyword.
      expect(InventoryMovementType.returned.wireName, 'return');
      expect(InventoryMovementType.openingBalance.wireName, 'opening_balance');
    });

    test('an unknown type reads as legacy', () {
      expect(inventoryMovementTypeFromWire('transferred'),
          InventoryMovementType.legacy);
      expect(inventoryMovementTypeFromWire(null), InventoryMovementType.legacy);
    });
  });

  group('item state', () {
    test('low stock is at or below the threshold, not just below', () {
      expect(_item(quantity: 5, threshold: 5).isLowStock, isTrue);
      expect(_item(quantity: 4, threshold: 5).isLowStock, isTrue);
      expect(_item(quantity: 6, threshold: 5).isLowStock, isFalse);
    });

    test('a draft is not usable for movements until confirmed', () {
      expect(_item(isDraft: true).isUsable, isFalse);
      expect(_item(isDraft: false).isUsable, isTrue);
    });

    test('an item with no event link is not usable either', () {
      final orphan = _item(eventId: null);
      expect(orphan.needsEventLink, isTrue);
      expect(orphan.isUsable, isFalse);
    });

    test('empty stock is a precondition for deletion, not a guarantee', () {
      // The backend still refuses if there is any transaction provenance.
      expect(_item(quantity: 0).isEmpty, isTrue);
      expect(_item(quantity: 1).isEmpty, isFalse);
    });
  });

  group('movements from purchases', () {
    test('a purchase-sourced movement is marked as such', () {
      final movement = InventoryMovement.fromJson({
        'id': 'm1',
        'inventory_id': 'i1',
        'event_id': 'e1',
        'change_qty': 4,
        'transaction_type': 'purchase',
        'reason': 'Completed purchase',
        'performed_by': 'u1',
        'expense_item_id': 'li1',
        'created_at': '2026-09-21T10:00:00Z',
      });

      expect(movement.isFromPurchase, isTrue);
      expect(movement.isIncoming, isTrue);
      expect(movement.type, InventoryMovementType.purchase);
    });

    test('a hand-recorded movement is not', () {
      final movement = InventoryMovement.fromJson({
        'id': 'm2',
        'inventory_id': 'i1',
        'event_id': 'e1',
        'change_qty': -2,
        'transaction_type': 'issue',
        'reason': 'Taken to the venue',
        'performed_by': 'u1',
        'expense_item_id': null,
        'created_at': '2026-09-22T10:00:00Z',
      });

      expect(movement.isFromPurchase, isFalse);
      expect(movement.isIncoming, isFalse);
    });
  });
}
