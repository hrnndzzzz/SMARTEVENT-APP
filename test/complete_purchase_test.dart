import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/complete_purchase_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Purchase completion is the only step that moves stock, and it runs once.
///
/// The rules are tested directly against the validator rather than by
/// driving the form, so each one is pinned individually instead of only the
/// first that happens to fire.
ExpenseLine _assetLine({
  String id = 'line-1',
  String name = 'Folding chairs',
  double amount = 1200,
  int quantity = 4,
}) {
  return ExpenseLine(
    id: id,
    expenseId: 'exp-1',
    name: name,
    amount: amount,
    category: ItemCategory.asset,
    quantity: quantity,
    unit: 'pcs',
    convertedInventoryId: null,
    createdAt: DateTime(2026, 9, 20),
  );
}

final _today = DateTime(2026, 9, 30);

/// A complete, valid submission. Individual tests override one field to
/// show that field is what makes it fail.
String? check({
  List<ExpenseLine>? assetLines,
  DateTime? paidOn,
  DateTime? receivedOn,
  String rawPaidAmount = '1200.00',
  double expenseTotal = 1200,
  String reference = 'PAY-2026-001',
  String vendor = 'Supplier Co',
  Map<String, String>? quantities,
  Map<String, String>? units,
}) {
  final lines = assetLines ?? [_assetLine()];
  return purchaseCompletionProblem(
    assetLines: lines,
    paidOn: paidOn ?? DateTime(2026, 9, 28),
    receivedOn: receivedOn ?? DateTime(2026, 9, 29),
    rawPaidAmount: rawPaidAmount,
    expenseTotal: expenseTotal,
    reference: reference,
    vendor: vendor,
    quantities: quantities ?? {for (final l in lines) l.id: '4'},
    units: units ?? {for (final l in lines) l.id: 'pcs'},
    today: _today,
  );
}

void main() {
  group('purchase completion rules', () {
    test('a complete, valid submission passes', () {
      expect(check(), isNull);
    });

    test('there must be at least one asset line', () {
      // Consumables never enter stock through this flow.
      expect(check(assetLines: const []), contains('no asset lines'));
    });

    test('both dates are required', () {
      // Called directly: the helper's defaults would fill an omitted date
      // back in, so a missing one has to be passed explicitly.
      String? withDates({DateTime? paidOn, DateTime? receivedOn}) {
        final line = _assetLine();
        return purchaseCompletionProblem(
          assetLines: [line],
          paidOn: paidOn,
          receivedOn: receivedOn,
          rawPaidAmount: '1200.00',
          expenseTotal: 1200,
          reference: 'PAY-2026-001',
          vendor: 'Supplier Co',
          quantities: {line.id: '4'},
          units: {line.id: 'pcs'},
          today: _today,
        );
      }

      expect(
        withDates(receivedOn: DateTime(2026, 9, 29)),
        contains('date this was paid'),
      );
      expect(
        withDates(paidOn: DateTime(2026, 9, 28)),
        contains('date this was received'),
      );
    });

    test('neither date may be in the future', () {
      expect(
        check(paidOn: DateTime(2026, 10, 5)),
        contains('cannot be in the future'),
      );
      expect(
        check(receivedOn: DateTime(2026, 10, 5)),
        contains('cannot be in the future'),
      );
    });

    test('today itself is allowed', () {
      // The boundary matters: paying and receiving today is normal.
      expect(check(paidOn: _today, receivedOn: _today), isNull);
    });

    test('the full amount must equal the expense total', () {
      expect(
        check(rawPaidAmount: '1100.00'),
        contains('must equal the expense total'),
      );
      expect(
        check(rawPaidAmount: '1300.00'),
        contains('must equal the expense total'),
      );
    });

    test('a sub-cent difference is treated as equal', () {
      expect(check(rawPaidAmount: '1200.00', expenseTotal: 1200.001), isNull);
    });

    test('the amount still has to be well-formed money', () {
      expect(check(rawPaidAmount: '1200.505'), contains('two decimal'));
      expect(check(rawPaidAmount: '-1200.00'), contains('negative'));
      expect(check(rawPaidAmount: ''), contains('Enter an amount'));
    });

    test('reference and supplier are required', () {
      expect(check(reference: '   '), contains('payment reference'));
      expect(check(vendor: '   '), contains('supplier'));
    });

    test('each line needs a positive received quantity', () {
      expect(
        check(quantities: {'line-1': '0'}),
        contains('quantity received'),
      );
      expect(
        check(quantities: {'line-1': '-2'}),
        contains('quantity received'),
      );
      expect(
        check(quantities: {'line-1': 'four'}),
        contains('quantity received'),
      );
    });

    test('each line needs a unit', () {
      expect(check(units: {'line-1': '  '}), contains('unit'));
    });

    test('a second line is checked too, not just the first', () {
      final lines = [_assetLine(), _assetLine(id: 'line-2', name: 'Tables')];
      expect(
        check(
          assetLines: lines,
          quantities: {'line-1': '4', 'line-2': '0'},
        ),
        contains('Tables'),
      );
    });
  });

  group('the form', () {
    Widget host({required List<ExpenseLine> lines}) {
      return ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: CompletePurchaseScreen(
            expense: ExpenseEntry(
              remoteId: 'exp-1',
              vendor: 'Supplier Co',
              amount: 1200,
              category: 'Equipment',
              status: ExpenseStatus.approved,
            ),
            assetLines: lines,
          ),
        ),
      );
    }

    testWidgets('prefills the paid amount with the expense total',
        (tester) async {
      await tester.pumpWidget(host(lines: [_assetLine()]));
      // It must match exactly, so making the user retype invites error.
      expect(find.text('1200.00'), findsOneWidget);
    });

    testWidgets('prefills each line with its ordered quantity and unit',
        (tester) async {
      await tester.pumpWidget(host(lines: [_assetLine(quantity: 4)]));

      expect(find.text('Folding chairs'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('pcs'), findsOneWidget);
    });

    testWidgets('says plainly when there are no asset lines', (tester) async {
      await tester.pumpWidget(host(lines: const []));
      expect(find.textContaining('No asset lines on this expense'),
          findsOneWidget);
    });

    testWidgets('states that the step runs only once', (tester) async {
      await tester.pumpWidget(host(lines: [_assetLine()]));
      expect(find.textContaining('cannot be repeated'), findsOneWidget);
    });
  });
}
