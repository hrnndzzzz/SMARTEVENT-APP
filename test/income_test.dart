import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/income.dart';
import 'package:smartevent/api/models/receipt.dart';

/// Whether income counts toward totals depends entirely on its receipt's
/// review status, so misreading that produces wrong financial figures.
Income _income({
  String receiptStatus = 'clear',
  double amount = 1000,
  String sourceType = 'sponsorship',
}) {
  return Income.fromJson({
    'id': 'i1',
    'event_id': 'e1',
    'source': 'ABC Corporation',
    'source_type': sourceType,
    'purpose': 'Venue sponsorship',
    'amount': amount,
    'received_on': '2026-09-20',
    'receipt_review_status': receiptStatus,
    'recorded_by': 'u1',
    'created_at': '2026-09-20T10:00:00Z',
  });
}

void main() {
  group('fund source wire values', () {
    test('round-trips every source', () {
      for (final source in FundSource.values) {
        expect(fundSourceFromWire(source.wireName), source);
      }
    });

    test('uses the snake_case the backend expects', () {
      expect(FundSource.registrationFees.wireName, 'registration_fees');
      expect(FundSource.sponsorship.wireName, 'sponsorship');
      expect(FundSource.donation.wireName, 'donation');
      expect(FundSource.other.wireName, 'other');
    });

    test('an unknown source falls back to other', () {
      // Matches the backend's own default; an unrecognized source is
      // untyped rather than a new category.
      expect(fundSourceFromWire('grant'), FundSource.other);
      expect(fundSourceFromWire(null), FundSource.other);
    });

    test('every source has a label and a hint', () {
      for (final source in FundSource.values) {
        expect(source.label, isNotEmpty, reason: source.name);
        expect(source.hint, isNotEmpty, reason: source.name);
      }
    });
  });

  group('withholding', () {
    test('a clear receipt counts', () {
      final income = _income(receiptStatus: 'clear');
      expect(income.isWithheld, isFalse);
      expect(income.withheldReason, isEmpty);
    });

    test('a cleared receipt also counts', () {
      // Reviewed and found fine — it counts like any other.
      expect(_income(receiptStatus: 'cleared').isWithheld, isFalse);
    });

    test('pending is withheld and says why', () {
      final income = _income(receiptStatus: 'pending');
      expect(income.isWithheld, isTrue);
      expect(income.withheldReason, contains('reviewed'));
    });

    test('rejected is withheld and says why', () {
      final income = _income(receiptStatus: 'rejected');
      expect(income.isWithheld, isTrue);
      expect(income.withheldReason, contains('rejected'));
    });

    test('an unparseable receipt status withholds rather than counts', () {
      // receiptReviewStatusFromWire defaults unknown to pending, so an
      // unrecognized state keeps the money out of totals instead of
      // quietly adding it.
      final income = _income(receiptStatus: 'something-new');
      expect(income.receiptReviewStatus, ReceiptReviewStatus.pending);
      expect(income.isWithheld, isTrue);
    });
  });

  group('parsing', () {
    test('keeps both the payer and the source type', () {
      final income = _income(sourceType: 'donation');
      // The breakdown needs the type; a person reading the ledger needs
      // the actual name. Both are kept.
      expect(income.source, 'ABC Corporation');
      expect(income.sourceType, FundSource.donation);
    });

    test('reads the amount and date', () {
      final income = _income(amount: 2500.5);
      expect(income.amount, 2500.5);
      expect(income.receivedOn, DateTime(2026, 9, 20));
    });
  });
}
