import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/state/school_calendar.dart';

/// The holiday rule is derived rather than typed, which is only an
/// improvement if the derivation is actually right. So it is checked
/// against the 2026 proclamation, date and weekday both — a wrong
/// Easter would still land on a Thursday, so the day of the week alone
/// would not catch it, and neither would the date alone catch a year
/// being read off by one.
void main() {
  group('the 2026 regular holidays come out as proclaimed', () {
    const proclaimed = <(int, int), (String, int)>{
      (1, 1): ("New Year's Day", DateTime.thursday),
      (4, 2): ('Maundy Thursday', DateTime.thursday),
      (4, 3): ('Good Friday', DateTime.friday),
      (4, 9): ('Araw ng Kagitingan', DateTime.thursday),
      (5, 1): ('Labor Day', DateTime.friday),
      (6, 12): ('Independence Day', DateTime.friday),
      (8, 31): ('National Heroes Day', DateTime.monday),
      (11, 30): ('Bonifacio Day', DateTime.monday),
      (12, 25): ('Christmas Day', DateTime.friday),
      (12, 30): ('Rizal Day', DateTime.wednesday),
    };

    proclaimed.forEach((when, what) {
      final (month, day) = when;
      final (name, weekday) = what;
      test('$name falls on 2026-$month-$day', () {
        final date = DateTime(2026, month, day);
        expect(date.weekday, weekday, reason: 'the pasted list says so');
        expect(SchoolCalendar.holidayOn(date), name);
      });
    });

    test('and there are exactly ten of them', () {
      expect(SchoolCalendar.regularHolidays(2026), hasLength(10));
    });
  });

  test('2027 is derived without anybody typing it', () {
    // The whole point of computing them. Easter 2027 is 28 March, so
    // Holy Week moves three weeks earlier than 2026's — exactly the
    // kind of shift a table typed once would get wrong in silence.
    expect(
      SchoolCalendar.holidayOn(DateTime(2027, 3, 25)),
      'Maundy Thursday',
    );
    expect(SchoolCalendar.holidayOn(DateTime(2027, 3, 26)), 'Good Friday');
    expect(
      SchoolCalendar.holidayOn(DateTime(2027, 8, 30)),
      'National Heroes Day',
    );
    expect(DateTime(2027, 8, 30).weekday, DateTime.monday);
    // And the fixed ones stay put.
    expect(SchoolCalendar.holidayOn(DateTime(2027, 6, 12)), 'Independence Day');
  });

  test('Easter is right for a century it will never see', () {
    // Guards the computus itself rather than the years in front of us:
    // the algorithm's century terms are the part that is easy to get
    // subtly wrong, and they do nothing at all within one century.
    expect(SchoolCalendar.holidayOn(DateTime(2030, 4, 18)), 'Maundy Thursday');
    expect(SchoolCalendar.holidayOn(DateTime(2100, 3, 26)), 'Good Friday');
  });

  group('what the date field refuses', () {
    final today = DateTime(2026, 11, 16);

    test('a day that has gone by', () {
      expect(
        SchoolCalendar.refusal(DateTime(2026, 11, 15), today: today),
        contains('already gone by'),
      );
      expect(SchoolCalendar.refusal(today, today: today), isNull);
    });

    test('a holiday, by name', () {
      expect(
        SchoolCalendar.refusal(DateTime(2026, 12, 25), today: today),
        'Christmas Day is a holiday — there are no classes.',
      );
    });

    test('an ordinary school day goes through', () {
      expect(SchoolCalendar.refusal(DateTime(2026, 11, 18), today: today),
          isNull);
      expect(
        SchoolCalendar.selectable(DateTime(2026, 11, 18), today: today),
        isTrue,
      );
    });
  });

  group('what it only warns about', () {
    test('a weekend is allowed, and said out loud', () {
      // Orgs do run Saturday activities. A form that refuses them is a
      // form people fill in with a lie.
      final saturday = DateTime(2026, 11, 21);
      expect(saturday.weekday, DateTime.saturday);
      expect(SchoolCalendar.refusal(saturday, today: DateTime(2026, 11, 16)),
          isNull);
      expect(SchoolCalendar.caution(saturday), contains('weekend'));
    });

    test('a date outside the school year on the form', () {
      expect(
        SchoolCalendar.caution(DateTime(2026, 9, 1), schoolYear: '2025-2026'),
        contains('outside 2025-2026'),
      );
      expect(
        SchoolCalendar.caution(DateTime(2026, 2, 3), schoolYear: '2025-2026'),
        isNull,
      );
    });

    test('a school year it cannot read never refuses anything', () {
      // A rule that cannot parse its own input must fall silent, not
      // start rejecting dates.
      expect(SchoolCalendar.withinSchoolYear(DateTime(2026, 2, 3), 'AY 25-26'),
          isTrue);
      expect(SchoolCalendar.withinSchoolYear(DateTime(2026, 2, 3), ''), isTrue);
    });
  });

  group('the time window', () {
    test('midnight is not a time anybody holds an activity at', () {
      expect(
        SchoolCalendar.timeRefusal(const SapTime(0, 0)),
        contains('between'),
      );
      expect(SchoolCalendar.timeRefusal(const SapTime(23, 30)), isNotNull);
      expect(SchoolCalendar.timeRefusal(const SapTime(5, 59)), isNotNull);
    });

    test('the ends of the window are inside it', () {
      expect(SchoolCalendar.timeRefusal(SchoolCalendar.earliest), isNull);
      expect(SchoolCalendar.timeRefusal(SchoolCalendar.latest), isNull);
      expect(SchoolCalendar.timeRefusal(const SapTime(13, 0)), isNull);
    });
  });
}
