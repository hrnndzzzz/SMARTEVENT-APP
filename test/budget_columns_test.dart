import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';

/// The paper's breakdown reads across: Snacks · 150 · 10.00 · 1,500.00.
///
/// Before the backend carried quantity and unit cost, the 150 and the
/// 10.00 were flattened into the particulars text and the printed form
/// stopped matching the paper. The backend took them on 24 Oct; this is
/// the client's half.
void main() {
  group('on the wire', () {
    test('a full row carries all four columns', () {
      const row = SapBudgetItem(
        particulars: 'Snacks',
        quantity: 150,
        unitCost: '10.00',
        amount: '1500.00',
      );

      expect(row.toJson(), {
        'particulars': 'Snacks',
        'quantity': 150,
        'unit_cost': '10.00',
        'amount': '1500.00',
      });
    });

    test('an ordinary row leaves unit cost out rather than sending null', () {
      const row = SapBudgetItem(particulars: 'Speaker', amount: '2000.00');

      expect(row.toJson(), {
        'particulars': 'Speaker',
        'quantity': 1,
        'amount': '2000.00',
      });
      expect(row.toJson().containsKey('unit_cost'), isFalse);
    });

    test('money stays the string it was typed as', () {
      // The server compares this decimal against the stated total, so
      // rounding it through a double is how an unexplainable 422 appears.
      const row = SapBudgetItem(
        particulars: 'Materials',
        quantity: 3,
        unitCost: '33.33',
        amount: '99.99',
      );

      expect(row.toJson()['unit_cost'], isA<String>());
      expect(row.toJson()['amount'], '99.99');
    });
  });

  group('reading back', () {
    test('a row the server saved with all four', () {
      final row = SapBudgetItem.fromJson(const {
        'particulars': 'Snacks',
        'quantity': 150,
        'unit_cost': '10.00',
        'amount': '1500.00',
      });

      expect(row.quantity, 150);
      expect(row.unitCost, '10.00');
      expect(row.amount, '1500.00');
    });

    test('a row saved before the columns existed', () {
      // His handoff is explicit: reading old rows does not backfill
      // their missing keys, so the client decides what absent means.
      final row = SapBudgetItem.fromJson(const {
        'particulars': 'Speaker',
        'amount': '2000.00',
      });

      expect(row.quantity, 1, reason: 'absent means one of the thing');
      expect(row.unitCost, isNull);
    });

    test('a numeric unit cost is kept as text, not rounded', () {
      final row = SapBudgetItem.fromJson(const {
        'particulars': 'Token',
        'unit_cost': 10,
        'amount': '10',
      });

      expect(row.unitCost, '10');
    });
  });

  test('amount is authoritative, not derived', () {
    // The server does not work amount out from quantity and unit cost,
    // and the paper sometimes rounds — so a row may state all three
    // without them multiplying out, and the client must not "correct" it.
    const row = SapBudgetItem(
      particulars: 'Snacks',
      quantity: 3,
      unitCost: '10.00',
      amount: '25.00',
    );

    expect(row.toJson()['amount'], '25.00');
  });
}
