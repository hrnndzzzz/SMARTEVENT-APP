import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/academic.dart';

/// School year, semester and scope are validated by the backend, so getting
/// them wrong here means a 422 the user cannot act on. These pin the rules
/// stated in `FRONTEND_README.md` §5.
void main() {
  group('school year validity', () {
    test('accepts two consecutive years', () {
      expect(SchoolYear.isValid('2026-2027'), isTrue);
      expect(SchoolYear.isValid('2019-2020'), isTrue);
    });

    test('rejects a two-year span', () {
      // The example the contract calls out explicitly.
      expect(SchoolYear.isValid('2026-2028'), isFalse);
    });

    test('rejects a reversed or equal pair', () {
      expect(SchoolYear.isValid('2027-2026'), isFalse);
      expect(SchoolYear.isValid('2026-2026'), isFalse);
    });

    test('rejects malformed input', () {
      expect(SchoolYear.isValid('2026'), isFalse);
      expect(SchoolYear.isValid('2026/2027'), isFalse);
      expect(SchoolYear.isValid('26-27'), isFalse);
      expect(SchoolYear.isValid(''), isFalse);
      expect(SchoolYear.isValid('abcd-efgh'), isFalse);
    });

    test('tolerates surrounding whitespace', () {
      expect(SchoolYear.isValid('  2026-2027 '), isTrue);
    });

    test('formats and reads back the starting year', () {
      expect(SchoolYear.format(2026), '2026-2027');
      expect(SchoolYear.startYearOf('2026-2027'), 2026);
      expect(SchoolYear.startYearOf('2026-2028'), isNull);
    });
  });

  group('school year options', () {
    test('suggestions are valid and newest first', () {
      final options = SchoolYear.suggestions(DateTime(2026, 9, 29));

      expect(options, isNotEmpty);
      for (final option in options) {
        expect(SchoolYear.isValid(option), isTrue, reason: option);
      }
      final starts = options.map(SchoolYear.startYearOf).toList();
      final sorted = [...starts]..sort((a, b) => b!.compareTo(a!));
      expect(starts, sorted);
    });

    test('a year starting in September belongs to that year', () {
      expect(SchoolYear.suggestions(DateTime(2026, 9, 1)), contains('2026-2027'));
    });

    test('a date in January still belongs to the previous start year', () {
      expect(SchoolYear.suggestions(DateTime(2026, 1, 15)), contains('2025-2026'));
    });

    test('merging keeps backend years and drops invalid ones', () {
      final merged = SchoolYear.mergeOptions(
        ['2019-2020', '2026-2028', 'nonsense'],
        DateTime(2026, 9, 29),
      );

      expect(merged, contains('2019-2020'));
      expect(merged, isNot(contains('2026-2028')));
      expect(merged, isNot(contains('nonsense')));
      // Never empty, so the picker always has something even offline.
      expect(merged.length, greaterThan(1));
    });

    test('merging does not duplicate a year the backend already knows', () {
      final merged = SchoolYear.mergeOptions(
        ['2026-2027'],
        DateTime(2026, 9, 29),
      );
      expect(merged.where((y) => y == '2026-2027').length, 1);
    });
  });

  group('semester wire values', () {
    test('round-trips every value', () {
      for (final semester in Semester.values) {
        expect(semesterFromWire(semester.wireName), semester);
      }
    });

    test('uses the ordinal spellings the backend expects', () {
      expect(Semester.first.wireName, '1st');
      expect(Semester.second.wireName, '2nd');
      expect(Semester.summer.wireName, 'summer');
    });

    test('unknown or absent reads as not set', () {
      expect(semesterFromWire('third'), isNull);
      expect(semesterFromWire(null), isNull);
      expect(semesterFromWire('1ST'), isNull, reason: 'case matters');
    });
  });

  group('event scope wire values', () {
    test('round-trips every value', () {
      for (final scope in EventScope.values) {
        expect(eventScopeFromWire(scope.wireName), scope);
      }
    });

    test('unknown or absent reads as not set', () {
      expect(eventScopeFromWire('school_wide'), isNull);
      expect(eventScopeFromWire(null), isNull);
    });
  });
}
