import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/demo_data.dart';
import 'package:smartevent/theme/peso.dart';

/// The paper's breakdown reads across: Snacks · 150 · 10.00 · 1,500.00.
///
/// Before the backend carried quantity and unit cost, the 150 and the
/// 10.00 were flattened into the particulars text and the printed form
/// stopped matching the paper. The backend took them on 24 Oct; this is
/// the client's half.
void main() {
  _moneyFormat();
  _demoRows();

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

/// The breakdown row and the SDS summary show the same figures, and used
/// to disagree: Part 3 had its own peso helper with no thousands
/// separator, so one screen read 1500.00 where the other, and the paper,
/// read 1,500.00.
void _moneyFormat() {
  group('money reads the same everywhere', () {
    test('thousands are grouped, as the paper writes them', () {
      expect(peso(1500), '\u20b11,500.00');
      expect(peso(35550), '\u20b135,550.00');
    });

    test('centavos survive', () {
      expect(peso(99.99), '\u20b199.99');
    });
  });
}

/// The demo is what a panel sees. Rows with only a total cannot show the
/// quantity and unit cost columns at all, so at least one seeded row has
/// to carry them — and every row's columns still have to agree with its
/// stated amount, or the demo shows arithmetic that does not add up.
void _demoRows() {
  group('the seeded breakdowns', () {
    test('show the paper\'s columns somewhere', () {
      final app = AppState()..enterDemo(role: UserRole.treasurer);
      final rows = [
        for (final event in app.events) ...DemoProposals.budgetFor(event),
      ];

      expect(rows, isNotEmpty);
      expect(
        rows.where((r) => r.quantity > 1 && r.unitCost != null),
        isNotEmpty,
        reason: 'otherwise the demo cannot show the columns at all',
      );
      expect(
        rows.where((r) => r.quantity == 1 && r.unitCost == null),
        isNotEmpty,
        reason: 'and a flat-fee row is the other half of the story',
      );
    });

    test('multiply out, where they state all three', () {
      final app = AppState()..enterDemo(role: UserRole.treasurer);
      final rows = [
        for (final event in app.events) ...DemoProposals.budgetFor(event),
      ].where((r) => r.unitCost != null);

      for (final row in rows) {
        final unit = (double.parse(row.unitCost!) * 100).round();
        expect(
          unit * row.quantity,
          (double.parse(row.amount) * 100).round(),
          reason: '${row.particulars} does not add up on screen',
        );
      }
    });
  });
}
