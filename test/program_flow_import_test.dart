import 'package:flutter_test/flutter_test.dart';

import 'package:smartevent/state/program_flow_import.dart';

/// Reading a programme out of a file instead of typing sixteen rows.
///
/// Asked for from a handset: "if keri sa program flow mag attached ng
/// file mas okay sana para may option instead na isa isa pa manually
/// type ang prgram flow".
void main() {
  group('what it reads', () {
    test('plain comma-separated rows', () {
      final out = ProgramFlowFile.parse(
        '08:00, 08:30, Registration\n'
        '08:30, 09:00, Opening ceremony\n',
      );

      expect(out.problems, isEmpty);
      expect(out.rows, hasLength(2));
      expect(out.rows.first.activity, 'Registration');
      expect(out.rows.first.start.label, '8:00 AM');
      expect(out.rows.last.end.label, '9:00 AM');
    });

    test('twelve-hour times, including the two that trip people up', () {
      final out = ProgramFlowFile.parse(
        '12:00 AM, 12:30 AM, Midnight vigil\n'
        '12:00 PM, 1:00 PM, Lunch\n',
      );

      expect(out.problems, isEmpty);
      // 12 AM is midnight and 12 PM is noon; the obvious arithmetic
      // gets both backwards.
      expect(out.rows[0].start.hour, 0);
      expect(out.rows[1].start.hour, 12);
      expect(out.rows[1].end.hour, 13);
    });

    test('a dash between the times, the way programmes are written', () {
      final out = ProgramFlowFile.parse('09:00-10:30, Keynote\n');

      expect(out.problems, isEmpty);
      expect(out.rows.single.activity, 'Keynote');
      expect(out.rows.single.end.label, '10:30 AM');
    });

    test('an activity keeps its own commas', () {
      final out = ProgramFlowFile.parse('12:00, 13:00, Lunch, then photos\n');

      expect(out.problems, isEmpty);
      expect(out.rows.single.activity, 'Lunch, then photos');
    });

    test('tabs and semicolons separate too, and blank lines are skipped', () {
      final out = ProgramFlowFile.parse(
        '08:00\t08:30\tRegistration\n'
        '\n'
        '08:30; 09:00; Opening\n',
      );

      expect(out.problems, isEmpty);
      expect(out.rows, hasLength(2));
    });

    test('a header line is not reported as a bad row', () {
      final out = ProgramFlowFile.parse(
        'Start, End, Activity\n'
        '08:00, 08:30, Registration\n',
      );

      expect(out.problems, isEmpty);
      expect(out.rows, hasLength(1));
    });
  });

  group('what it refuses, and says so about', () {
    test('a bad time is named with its line number', () {
      final out = ProgramFlowFile.parse(
        '08:00, 08:30, Registration\n'
        'half nine, 10:00, Keynote\n',
      );

      // The good row still comes through: one bad line should not cost
      // the whole programme.
      expect(out.rows, hasLength(1));
      expect(out.problems, hasLength(1));
      expect(out.problems.single, contains('Line 2'));
      expect(out.problems.single, contains('half nine'));
    });

    test('a row that ends before it starts', () {
      final out = ProgramFlowFile.parse('10:00, 09:00, Backwards\n');

      expect(out.rows, isEmpty);
      expect(out.problems.single, contains('ends before it starts'));
    });

    test('a row with no activity', () {
      final out = ProgramFlowFile.parse('08:00, 08:30,\n');

      expect(out.rows, isEmpty);
      expect(out.problems.single, contains('no activity'));
    });

    test('an hour that does not exist', () {
      final out = ProgramFlowFile.parse(
        '25:00, 26:00, Nope\n'
        '13:70, 14:00, Also nope\n',
      );

      expect(out.rows, isEmpty);
      expect(out.problems, hasLength(2));
    });

    test('rows past the form\'s limit, named rather than dropped', () {
      final many = List.generate(
        ProgramFlowFile.limit + 4,
        (i) => '08:00, 09:00, Slot $i',
      ).join('\n');

      final out = ProgramFlowFile.parse(many);

      expect(out.rows, hasLength(ProgramFlowFile.limit));
      // Silently keeping the first sixteen would leave somebody
      // wondering where the rest went.
      expect(out.problems.single, contains('${ProgramFlowFile.limit} rows'));
    });

    test('an empty file says so instead of succeeding with nothing', () {
      final out = ProgramFlowFile.parse('   \n\n');

      expect(out.rows, isEmpty);
      expect(out.problems.single, contains('nothing in that file'));
    });
  });
}
