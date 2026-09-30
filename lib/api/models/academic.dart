/// Academic metadata every event carries: school year, semester and scope.
///
/// The exact wire values come from `FRONTEND_README.md` §5 and are not
/// negotiable — the backend validates them:
///
///   * school year — two consecutive years, `2026-2027`. `2026-2028` is not
///     a school year and is rejected.
///   * semester — `1st`, `2nd`, `summer`.
///   * event scope — `departmental`, `organizational`.
library;

/// Semester. The Dart names and the wire values differ, so never send
/// `.name`.
enum Semester { first, second, summer }

extension SemesterNaming on Semester {
  String get wireName => switch (this) {
        Semester.first => '1st',
        Semester.second => '2nd',
        Semester.summer => 'summer',
      };

  String get label => switch (this) {
        Semester.first => 'First semester',
        Semester.second => 'Second semester',
        Semester.summer => 'Summer',
      };

  /// Compact form for list rows and chips.
  String get shortLabel => switch (this) {
        Semester.first => '1st sem',
        Semester.second => '2nd sem',
        Semester.summer => 'Summer',
      };
}

/// Null for anything unrecognized, so an unexpected value shows as
/// "not set" rather than being silently coerced to a real semester.
Semester? semesterFromWire(String? value) => switch (value) {
      '1st' => Semester.first,
      '2nd' => Semester.second,
      'summer' => Semester.summer,
      _ => null,
    };

/// Whether an event belongs to one department or to the organization as a
/// whole. Reports can be filtered either way, so this is not cosmetic.
enum EventScope { departmental, organizational }

extension EventScopeNaming on EventScope {
  /// Here the Dart name and the wire value happen to match.
  String get wireName => name;

  String get label => switch (this) {
        EventScope.departmental => 'Departmental',
        EventScope.organizational => 'Organizational',
      };

  String get description => switch (this) {
        EventScope.departmental =>
          'Run by one department. Requires a department.',
        EventScope.organizational =>
          'Run by the organization as a whole.',
      };
}

EventScope? eventScopeFromWire(String? value) => switch (value) {
      'departmental' => EventScope.departmental,
      'organizational' => EventScope.organizational,
      _ => null,
    };

/// School-year parsing and validation.
abstract final class SchoolYear {
  static final RegExp _pattern = RegExp(r'^(\d{4})-(\d{4})$');

  /// Two consecutive years, in order. `2026-2027` passes; `2026-2028`,
  /// `2027-2026` and `2026` do not.
  static bool isValid(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) return false;
    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2)!);
    return end == start + 1;
  }

  /// Builds the label for a year beginning in [startYear].
  static String format(int startYear) => '$startYear-${startYear + 1}';

  /// The starting year, or null when [value] isn't a valid school year.
  static int? startYearOf(String value) {
    if (!isValid(value)) return null;
    return int.parse(_pattern.firstMatch(value.trim())!.group(1)!);
  }

  /// Sensible options for a picker, newest first.
  ///
  /// Only a convenience: the backend does not derive the current school
  /// year, and a new event must be allowed to use a year that does not
  /// exist yet, so a form offering these must still accept a typed value.
  /// The June rollover is a local display convention, nothing more.
  static List<String> suggestions(
    DateTime now, {
    int back = 3,
    int forward = 1,
  }) {
    final currentStart = now.month >= 6 ? now.year : now.year - 1;
    return [
      for (var year = currentStart + forward; year >= currentStart - back; year--)
        format(year),
    ];
  }

  /// Merges the years the backend already knows about with local
  /// suggestions, newest first and without duplicates, so a picker shows
  /// real data first but is never empty.
  static List<String> mergeOptions(
    Iterable<String> known,
    DateTime now,
  ) {
    final valid = {
      ...known.where(isValid),
      ...suggestions(now),
    }.toList();
    valid.sort((a, b) => startYearOf(b)!.compareTo(startYearOf(a)!));
    return valid;
  }
}
