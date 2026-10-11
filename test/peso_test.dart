import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/theme/peso.dart';

/// Amounts are read aloud during a budget defence, so they are grouped.
void main() {
  test('groups thousands and keeps two decimals', () {
    expect(peso(38000), '₱38,000.00');
    expect(peso(1200.5), '₱1,200.50');
    expect(peso(999), '₱999.00');
    expect(peso(1000), '₱1,000.00');
    expect(peso(1234567.89), '₱1,234,567.89');
  });

  test('zero and small amounts carry no stray separator', () {
    expect(peso(0), '₱0.00');
    expect(peso(7.05), '₱7.05');
    expect(peso(100), '₱100.00');
  });

  test('a negative keeps its sign outside the glyph', () {
    expect(peso(-1200), '-₱1,200.00');
    expect(peso(-0.5), '-₱0.50');
  });

  test('the glanceable form drops the centavos', () {
    expect(peso(38000, decimals: 0), '₱38,000');
    expect(peso(1234567, decimals: 0), '₱1,234,567');
  });

  test('what it writes, it can read back', () {
    for (final value in [0.0, 7.05, 999.0, 38000.0, 1234567.89]) {
      expect(parsePeso(peso(value)), value);
    }
    // And what the app stored before the separators arrived.
    expect(parsePeso('₱38000.00'), 38000.0);
    expect(parsePeso('not money'), isNull);
  });
}
