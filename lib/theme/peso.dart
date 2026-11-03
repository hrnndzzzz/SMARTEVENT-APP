/// Peso amounts, formatted the one way.
///
/// `₱38000.00` is a number you have to count digits on. Grouping is the
/// whole point of the glyph being there, and a budget defence is an hour
/// of reading amounts aloud.
///
/// This lives beside the money text styles because the format and the
/// face are the same decision: `AppText.moneyLarge` sets how an amount
/// looks, [peso] sets what it says.
library;

/// `₱38,000.00`, or `-₱1,200.00` when it is negative.
///
/// [decimals] drops to 0 for the glanceable figures — a dashboard tile
/// says ₱38,000, not ₱38,000.00 — and stays at 2 wherever the centavos
/// are part of the record.
String peso(num value, {int decimals = 2}) {
  final sign = value < 0 ? '-' : '';
  return '$sign₱${grouped(value.abs(), decimals: decimals)}';
}

/// An amount held as text, shown as money.
///
/// `EventItem.budget` is a string whose shape depends on who wrote it:
/// the backend path stores it already formatted, while a locally created
/// or seeded event stores bare digits, and the SAP form parses those
/// digits back out of it. So the formatting happens where it is read.
/// Anything that parses as a number is formatted; anything else came in
/// formatted already and is left alone.
String pesoText(String value) {
  final amount = num.tryParse(value.trim());
  return amount == null ? value : peso(amount);
}

/// The digits alone, grouped in threes.
String grouped(num value, {int decimals = 2}) {
  final text = value.toStringAsFixed(decimals);
  final dot = text.indexOf('.');
  final whole = dot < 0 ? text : text.substring(0, dot);
  final rest = dot < 0 ? '' : text.substring(dot);

  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    // A separator every three digits, counted from the right, and never
    // leading.
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '$buffer$rest';
}

/// Reads back what [peso] wrote.
///
/// Amounts travel through the app as display strings in a few places, so
/// anything that parses one has to tolerate both the glyph and the
/// separators it now carries.
double? parsePeso(String text) =>
    double.tryParse(text.replaceAll(RegExp(r'[₱,\s]'), ''));
