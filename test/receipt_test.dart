import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/receipt.dart';

/// Receipt review status decides whether an expense can be approved and
/// whether an income counts toward totals, so reading it wrongly has real
/// financial consequences.
Receipt _receipt({
  String status = 'clear',
  List<String> similar = const [],
  bool flagged = false,
}) {
  return Receipt.fromJson({
    'id': 'r1',
    'organization_id': 'o1',
    'department_id': 'd1',
    'event_id': 'e1',
    'expense_id': 'x1',
    'income_id': null,
    'purpose': 'Catering',
    'receipt_url': 'https://example.org/r.png',
    'merchant': 'Shop',
    'receipt_number': 'A-1',
    'issued_on': '2026-09-20',
    'amount': 1200,
    'is_flagged': flagged,
    'similar_receipt_ids': similar,
    'review_status': status,
    'review_reason': null,
    'reviewed_by': null,
    'reviewed_at': null,
    'recorded_by': 'u1',
    'created_at': '2026-09-20T10:00:00Z',
  });
}

void main() {
  group('review status parsing', () {
    test('round-trips every status', () {
      for (final status in ReceiptReviewStatus.values) {
        expect(receiptReviewStatusFromWire(status.wireName), status);
      }
    });

    test('an unknown status reads as pending, not clear', () {
      // Erring toward "someone should look" is the safer mistake: reading
      // an unknown state as clear would let it through silently.
      expect(receiptReviewStatusFromWire('quarantined'),
          ReceiptReviewStatus.pending);
      expect(receiptReviewStatusFromWire(null), ReceiptReviewStatus.pending);
    });
  });

  group('what each status means', () {
    test('only pending is awaiting review', () {
      expect(_receipt(status: 'pending').isAwaitingReview, isTrue);
      for (final other in ['clear', 'cleared', 'rejected']) {
        expect(_receipt(status: other).isAwaitingReview, isFalse,
            reason: other);
      }
    });

    test('clear means nothing resembled it, not that it was approved', () {
      final receipt = _receipt(status: 'clear');
      expect(receipt.isAwaitingReview, isFalse);
      expect(receipt.isReviewSettled, isFalse,
          reason: 'no decision was ever made');
    });

    test('cleared and rejected are both settled', () {
      expect(_receipt(status: 'cleared').isReviewSettled, isTrue);
      expect(_receipt(status: 'rejected').isReviewSettled, isTrue);
    });

    test('every status explains its own consequence', () {
      for (final status in ReceiptReviewStatus.values) {
        expect(status.consequence, isNotEmpty, reason: status.name);
        expect(status.label, isNotEmpty, reason: status.name);
      }
      // The two that hold up money say so.
      expect(ReceiptReviewStatus.pending.consequence, contains('withheld'));
      expect(ReceiptReviewStatus.rejected.consequence, contains('withheld'));
    });
  });

  group('similarity', () {
    test('reports whether there is anything to compare', () {
      expect(_receipt().hasSimilar, isFalse);
      expect(_receipt(similar: ['r2', 'r3']).hasSimilar, isTrue);
      expect(_receipt(similar: ['r2', 'r3']).similarReceiptIds.length, 2);
    });

    test('a flag and a similarity are independent', () {
      // A receipt can be flagged without similar ones, and vice versa.
      expect(_receipt(flagged: true).isFlagged, isTrue);
      expect(_receipt(flagged: true).hasSimilar, isFalse);
      expect(_receipt(similar: ['r2']).isFlagged, isFalse);
    });
  });

  group('transaction link', () {
    test('knows whether it belongs to an expense or an income', () {
      expect(_receipt().isForExpense, isTrue);
    });
  });

  group('decisions', () {
    test('only cleared and rejected are submittable', () {
      // clear and pending are states the backend sets, not choices.
      expect(ReceiptDecision.values.map((d) => d.wireName),
          ['cleared', 'rejected']);
    });
  });
}
