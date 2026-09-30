import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/money.dart';

/// Money is sent to the backend as a decimal string, so these rules decide
/// what reaches a `Decimal` field. Getting them wrong means either a 422 the
/// user can't act on, or a silently wrong amount.
void main() {
  group('validation', () {
    test('accepts whole and two-decimal amounts', () {
      expect(MoneyInput.validate('1200'), isNull);
      expect(MoneyInput.validate('1200.5'), isNull);
      expect(MoneyInput.validate('1200.50'), isNull);
      expect(MoneyInput.validate('0.01'), isNull);
    });

    test('rejects more than two decimal places', () {
      expect(MoneyInput.validate('1200.505'), contains('two decimal'));
    });

    test('rejects negatives with a specific message', () {
      expect(MoneyInput.validate('-5'), contains('negative'));
    });

    test('rejects zero unless explicitly allowed', () {
      // Income, expense, receipt and payment amounts must be positive;
      // budget fields may be zero.
      expect(MoneyInput.validate('0'), contains('more than zero'));
      expect(MoneyInput.validate('0', allowZero: true), isNull);
      expect(MoneyInput.validate('0.00', allowZero: true), isNull);
    });

    test('rejects empty and non-numeric input', () {
      expect(MoneyInput.validate(''), contains('Enter an amount'));
      expect(MoneyInput.validate('   '), contains('Enter an amount'));
      expect(MoneyInput.validate('abc'), isNotNull);
      expect(MoneyInput.validate('1,200'), isNotNull);
      expect(MoneyInput.validate('₱1200'), isNotNull);
    });

    test('tolerates surrounding whitespace', () {
      expect(MoneyInput.validate('  1200.00  '), isNull);
    });
  });

  group('normalization', () {
    test('always produces exactly two decimal places', () {
      expect(MoneyInput.normalize('1200'), '1200.00');
      expect(MoneyInput.normalize('1200.5'), '1200.50');
      expect(MoneyInput.normalize('1200.50'), '1200.50');
      expect(MoneyInput.normalize('  7  '), '7.00');
    });

    test('returns null for anything it would not accept', () {
      expect(MoneyInput.normalize('-1'), isNull);
      expect(MoneyInput.normalize('1.234'), isNull);
      expect(MoneyInput.normalize('0'), isNull);
      expect(MoneyInput.normalize(''), isNull);
    });

    test('normalized output validates cleanly', () {
      for (final raw in ['1', '1.5', '99.99', '1200']) {
        final normalized = MoneyInput.normalize(raw)!;
        expect(MoneyInput.validate(normalized), isNull, reason: raw);
      }
    });
  });

  group('formatting a value that came from the backend', () {
    test('renders two decimal places', () {
      expect(MoneyInput.fromDouble(1200), '1200.00');
      expect(MoneyInput.fromDouble(0.1), '0.10');
    });

    test('output is accepted by validate, so it can be sent straight back', () {
      // Guards the round trip: read a double from the API, send it again.
      for (final value in [0.1, 1.005, 1200.0, 99.99]) {
        expect(MoneyInput.validate(MoneyInput.fromDouble(value)), isNull,
            reason: '$value');
      }
    });
  });
}
