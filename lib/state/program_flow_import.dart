import '../api/models/sap_proposal.dart';

/// What came out of a programme file.
typedef ProgramFlowImport = ({
  /// The rows that read cleanly, in file order.
  List<SapProgramFlowItem> rows,

  /// One line per row that did not, naming the line number and why.
  /// Shown rather than swallowed: a programme quietly two rows short
  /// is worse than one that says which two it could not read.
  List<String> problems,
});

/// Reads a programme out of a text or CSV file.
///
/// Asked for from a handset: "if keri sa program flow mag attached ng
/// file mas okay sana para may option instead na isa isa pa manually
/// type ang prgram flow". Sixteen slots typed one sheet at a time is
/// most of the work of Part 1, and the programme usually exists
/// already in whatever the organisation drafted it in.
///
/// ## What it accepts
///
/// One row per line, three fields: start, end, what happens.
///
///     08:00, 08:30, Registration
///     8:30 AM, 9:00 AM, Opening ceremony
///     09:00-10:30, Keynote
///
/// Commas, semicolons and tabs all separate. A time range joined by a
/// dash counts as the first two fields, because that is how a
/// programme is usually written down. A header line is skipped.
/// Anything the activity text contains after the first two fields is
/// kept whole, commas and all, so "Lunch, then photos" survives.
abstract final class ProgramFlowFile {
  /// Rows beyond this are refused by the form anyway.
  static const limit = SapProposal.maxCollectionItems;

  static ProgramFlowImport parse(String text) {
    final rows = <SapProgramFlowItem>[];
    final problems = <String>[];
    final lines = text.split(RegExp(r'\r\n|\r|\n'));

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final fields = _fields(line);
      if (fields == null) {
        // A header is the one unreadable line nobody wants reported.
        if (i == 0 && _looksLikeHeader(line)) continue;
        problems.add(
          'Line ${i + 1}: expected a start, an end and an '
          'activity — "$line"',
        );
        continue;
      }

      final (startText, endText, activity) = fields;
      final start = _time(startText);
      final end = _time(endText);

      if (start == null || end == null) {
        if (i == 0 && _looksLikeHeader(line)) continue;
        problems.add(
          'Line ${i + 1}: could not read '
          '"${start == null ? startText : endText}" as a time',
        );
        continue;
      }
      if (activity.isEmpty) {
        problems.add('Line ${i + 1}: no activity given');
        continue;
      }
      if (end.compareTo(start) < 0) {
        problems.add('Line ${i + 1}: $activity ends before it starts');
        continue;
      }
      if (rows.length >= limit) {
        problems.add('Line ${i + 1} and after: the form holds $limit rows');
        break;
      }

      rows.add(SapProgramFlowItem(start: start, end: end, activity: activity));
    }

    if (rows.isEmpty && problems.isEmpty) {
      problems.add('There was nothing in that file.');
    }
    return (rows: rows, problems: problems);
  }

  /// Splits one line into start, end and the rest.
  static (String, String, String)? _fields(String line) {
    // A dash between the first two times is how programmes are
    // normally written, so it separates like a comma would — but only
    // between them, never inside the activity text.
    final ranged = RegExp(
      r'^\s*([0-9]{1,2}:[0-9]{2}\s*(?:[AaPp][Mm])?)\s*[-–—]\s*'
      r'([0-9]{1,2}:[0-9]{2}\s*(?:[AaPp][Mm])?)\s*[,;\t]?\s*(.*)$',
    ).firstMatch(line);
    if (ranged != null) {
      return (
        ranged.group(1)!.trim(),
        ranged.group(2)!.trim(),
        ranged.group(3)!.trim(),
      );
    }

    final parts = line.split(RegExp(r'[,;\t]'));
    if (parts.length < 3) return null;
    // Only the first two separators count: the activity keeps its own
    // commas, so "Lunch, then photos" arrives whole.
    return (
      parts[0].trim(),
      parts[1].trim(),
      parts.sublist(2).join(',').trim(),
    );
  }

  static bool _looksLikeHeader(String line) {
    final first = line.split(RegExp(r'[,;\t]')).first.trim().toLowerCase();
    return first == 'start' || first == 'time' || first == 'from';
  }

  /// `08:30`, `8:30`, `8:30 AM`, `8:30PM`.
  static SapTime? _time(String raw) {
    final text = raw.trim().toUpperCase();
    final match = RegExp(
      r'^([0-9]{1,2}):([0-9]{2})\s*(AM|PM)?$',
    ).firstMatch(text);
    if (match == null) return null;

    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final meridiem = match.group(3);

    if (minute > 59) return null;
    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      // 12 AM is midnight and 12 PM is noon, which the obvious
      // arithmetic gets backwards.
      hour = hour % 12;
      if (meridiem == 'PM') hour += 12;
    } else if (hour > 23) {
      return null;
    }
    return SapTime(hour, minute);
  }
}
