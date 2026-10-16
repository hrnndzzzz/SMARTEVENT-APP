/// Money handling for amounts the backend stores as `Decimal`.
///
/// Amounts are sent as **strings**, not JSON numbers. The backend's own
/// documented example does this (`"paid_amount": "1200.00"`), and it is the
/// only way a value survives the trip exactly — a double can't represent
/// every two-decimal amount, and `Decimal` parses a string losslessly.
///
/// Nothing here computes balances. Remaining budget and stock are
/// server-owned and arrive already calculated; the app must never derive an
/// authoritative figure with floating-point arithmetic.
abstract final class MoneyInput {
  /// Digits with at most two decimal places. Leading `+`/`-` is rejected
  /// outright so a negative never reaches a field that forbids one.
  static final RegExp _pattern = RegExp(r'^\d+(\.\d{1,2})?$');

  /// Validates raw user input.
  ///
  /// Returns null when acceptable, otherwise a message to show. Set
  /// [allowZero] for budget fields, which may be zero; income, expense,
  /// receipt and payment amounts must be positive.
  static String? validate(String raw, {bool allowZero = false}) {
    final text = raw.trim();
    if (text.isEmpty) return 'Enter an amount.';

    if (!_pattern.hasMatch(text)) {
      if (text.startsWith('-')) return 'The amount cannot be negative.';
      if (RegExp(r'\.\d{3,}$').hasMatch(text)) {
        return 'Use at most two decimal places.';
      }
      return 'Enter a valid amount, like 1200.00.';
    }

    final value = double.tryParse(text);
    if (value == null) return 'Enter a valid amount, like 1200.00.';
    if (!allowZero && value == 0) return 'The amount must be more than zero.';

    return null;
  }

  /// Normalizes accepted input to the exact string to send, e.g. `1200.00`.
  /// Returns null when [raw] is not valid.
  static String? normalize(String raw, {bool allowZero = false}) {
    if (validate(raw, allowZero: allowZero) != null) return null;

    final text = raw.trim();
    final dot = text.indexOf('.');
    if (dot < 0) return '$text.00';

    final decimals = text.length - dot - 1;
    return decimals == 1 ? '${text}0' : text;
  }

  /// Formats a value that came *from* the backend for sending back, which
  /// is safe because it has already been through the server's own Decimal.
  static String fromDouble(double value) => value.toStringAsFixed(2);
}
