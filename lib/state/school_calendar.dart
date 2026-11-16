import '../api/models/sap_proposal.dart';

/// When an activity may be held, and when it may not.
///
/// Two separate questions, deliberately kept apart. A date the office
/// will never accept is **refused** at the picker, so it cannot be
/// chosen at all. A date that is merely a bad idea is **cautioned**, and
/// the proposer decides — some organisations really do hold things on a
/// Saturday, and a form that knows better than the people filling it in
/// is a form people route around.
///
/// ## Why the holidays are computed and not typed
///
/// A list of dates typed in is right for one year and quietly wrong
/// every year after, which is the worst way for a rule to fail: it keeps
/// answering, it just stops being true. Of the ten Philippine regular
/// holidays, seven sit on fixed dates set by law, and the other three
/// are computable — Maundy Thursday and Good Friday from Easter, and
/// National Heroes Day as the last Monday of August. So none of them
/// needs to be remembered.
///
/// What cannot be computed is the two Islamic holidays, Eid'l Fitr and
/// Eid'l Adha. They follow a lunar calendar and are fixed each year by
/// proclamation, so they live in [proclaimed] as the one short table
/// anybody has to top up — and the app is correct without it, just less
/// complete.
abstract final class SchoolCalendar {
  // ── Holidays ────────────────────────────────────────────────────────

  /// The Philippine regular holidays of [year], by date.
  ///
  /// Checked against the 2026 proclamation in
  /// `test/school_calendar_test.dart`, which is the only way to know the
  /// derivation is right rather than merely plausible.
  static Map<DateTime, String> regularHolidays(int year) {
    final easter = _easter(year);
    return {
      DateTime(year, 1, 1): "New Year's Day",
      easter.subtract(const Duration(days: 3)): 'Maundy Thursday',
      easter.subtract(const Duration(days: 2)): 'Good Friday',
      DateTime(year, 4, 9): 'Araw ng Kagitingan',
      DateTime(year, 5, 1): 'Labor Day',
      DateTime(year, 6, 12): 'Independence Day',
      _lastMondayOfAugust(year): 'National Heroes Day',
      DateTime(year, 11, 30): 'Bonifacio Day',
      DateTime(year, 12, 25): 'Christmas Day',
      DateTime(year, 12, 30): 'Rizal Day',
    };
  }

  /// The holidays that have to be looked up rather than worked out:
  /// Eid'l Fitr and Eid'l Adha, and any special non-working day the
  /// school decides to observe.
  ///
  /// Add a line when the proclamation comes out. Nothing breaks while it
  /// is empty — those dates simply go through like any other day.
  static const Map<(int year, int month, int day), String> proclaimed = {
    // (2026, 3, 20): "Eid'l Fitr",
    // (2026, 5, 27): "Eid'l Adha",
  };

  /// The name of the holiday on [date], or null if it is an ordinary day.
  static String? holidayOn(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final named = proclaimed[(day.year, day.month, day.day)];
    if (named != null) return named;
    return regularHolidays(day.year)[day];
  }

  // ── What the date field refuses ─────────────────────────────────────

  /// Why [date] cannot be the activity date, or null when it may be.
  ///
  /// [today] is injectable so the rule can be tested without waiting for
  /// the calendar to come round.
  static String? refusal(DateTime date, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(now.year, now.month, now.day);

    if (day.isBefore(start)) {
      return 'That day has already gone by.';
    }
    if (holidayOn(day) case final holiday?) {
      return '$holiday is a holiday — there are no classes.';
    }
    return null;
  }

  /// Whether [date] may be picked at all. The shape `showDatePicker`
  /// wants, so a refused day is greyed out rather than tapped and
  /// rejected.
  static bool selectable(DateTime date, {DateTime? today}) =>
      refusal(date, today: today) == null;

  /// Why [date] is a poor choice although it is allowed, or null.
  ///
  /// Said next to the field rather than in the way of it. A weekend
  /// activity is a real thing; one booked outside the school year the
  /// form itself names is usually a typo in one of the two.
  static String? caution(DateTime date, {String? schoolYear}) {
    final day = DateTime(date.year, date.month, date.day);
    if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
      return 'That is a weekend. Allowed, but check it is intended.';
    }
    if (schoolYear != null && !withinSchoolYear(day, schoolYear)) {
      return 'That is outside $schoolYear, the school year on this form.';
    }
    return null;
  }

  /// Whether [date] falls in [schoolYear], written as `2025-2026`.
  ///
  /// A school year runs June to May here, so `2025-2026` is June 2025 to
  /// May 2026. Anything unparseable returns true: a rule that cannot
  /// read its own input must not start refusing dates.
  static bool withinSchoolYear(DateTime date, String schoolYear) {
    final years = RegExp(
      r'(\d{4})\s*[-–]\s*(\d{4})',
    ).firstMatch(schoolYear.trim());
    if (years == null) return true;
    final from = DateTime(int.parse(years.group(1)!), 6, 1);
    final to = DateTime(int.parse(years.group(2)!), 5, 31);
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  // ── What the time fields refuse ─────────────────────────────────────

  /// The earliest an activity may start and the latest it may end.
  ///
  /// The picker let a proposal say 12:00 AM, which is not a time anybody
  /// holds a student activity at — it is what a time field returns when
  /// somebody taps through it. The window is wide enough for an early
  /// call time and a programme that runs long, and narrow enough that
  /// midnight is not reachable by accident.
  static const SapTime earliest = SapTime(6, 0);
  static const SapTime latest = SapTime(22, 0);

  /// Why [time] is not a usable activity time, or null when it is.
  static String? timeRefusal(SapTime time) {
    if (time.compareTo(earliest) < 0 || time.compareTo(latest) > 0) {
      return 'Activities run between ${earliest.label} and ${latest.label}.';
    }
    return null;
  }

  // ── The two derivations ─────────────────────────────────────────────

  /// Easter Sunday, by the anonymous Gregorian computus. Maundy Thursday
  /// and Good Friday are the three and two days before it.
  static DateTime _easter(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  /// National Heroes Day. August has 31 days, so the last Monday is
  /// found by walking back from the 31st.
  static DateTime _lastMondayOfAugust(int year) {
    var day = DateTime(year, 8, 31);
    while (day.weekday != DateTime.monday) {
      day = day.subtract(const Duration(days: 1));
    }
    return day;
  }
}
