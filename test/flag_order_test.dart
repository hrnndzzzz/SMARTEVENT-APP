import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/remote_expense.dart';
import 'package:smartevent/screens/risk_screen.dart';

/// Ordering the flagged list by what the record actually holds.
///
/// There is no severity on a flagged expense — only a reason, as free
/// text — so nothing here ranks by how bad something is. A real severity
/// would have to come from the backend.
void main() {
  RemoteExpense flagged({
    required String id,
    required double amount,
    DateTime? on,
    String? reason,
  }) => RemoteExpense(
    id: id,
    eventId: null,
    categoryId: 'cat',
    departmentId: null,
    organizationId: null,
    description: id,
    amount: amount,
    expenseDate: on,
    receiptUrl: null,
    ocrMerchant: null,
    ocrDate: null,
    ocrAmount: null,
    isFlagged: true,
    flagReason: reason,
    status: 'pending',
    recordedBy: 'someone',
    purchaseCompletedAt: null,
    paidOn: null,
    receivedOn: null,
    paymentMethod: null,
    paymentReference: null,
    purchaseVendor: null,
    paidAmount: null,
    createdAt: on ?? DateTime(2026),
    updatedAt: on ?? DateTime(2026),
  );

  final older = flagged(id: 'older', amount: 50, on: DateTime(2026, 1, 1));
  final newer = flagged(id: 'newer', amount: 10, on: DateTime(2026, 6, 1));
  final biggest = flagged(
    id: 'biggest',
    amount: 900,
    on: DateTime(2026, 3, 1),
    reason: 'Duplicate',
  );

  test('newest first', () {
    final sorted = FlagOrder.newest.apply([older, biggest, newer]);
    expect(sorted.map((e) => e.id), ['newer', 'biggest', 'older']);
  });

  test('largest first', () {
    final sorted = FlagOrder.largest.apply([older, newer, biggest]);
    expect(sorted.first.id, 'biggest');
    expect(sorted.last.id, 'newer');
  });

  test('by reason, with the unexplained ones last', () {
    final sorted = FlagOrder.reason.apply([older, biggest, newer]);
    expect(sorted.first.id, 'biggest', reason: 'the only one with a reason');
    expect(sorted.last.flagReason, isNull);
  });

  test('sorting never changes the list it was given', () {
    final original = [older, biggest, newer];
    final before = [...original];

    for (final order in FlagOrder.values) {
      order.apply(original);
    }

    expect(original.map((e) => e.id), before.map((e) => e.id));
  });

  test('and never loses or duplicates anything', () {
    for (final order in FlagOrder.values) {
      final sorted = order.apply([older, biggest, newer]);
      expect(sorted, hasLength(3), reason: order.name);
      expect({for (final e in sorted) e.id}, hasLength(3), reason: order.name);
    }
  });
}
