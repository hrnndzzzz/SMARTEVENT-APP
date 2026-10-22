/// What one row of a rejected roster workbook was wrong about.
///
/// The server validates the whole workbook before inserting anything, so
/// a refusal names every bad row rather than stopping at the first.
class RosterRowError {
  const RosterRowError({
    required this.row,
    required this.column,
    required this.message,
  });

  /// 1-based, as the spreadsheet numbers them.
  final int row;

  /// The column heading, so it can be found by eye in the workbook.
  final String column;

  final String message;

  factory RosterRowError.fromJson(Map<String, dynamic> json) => RosterRowError(
    row: (json['row'] as num?)?.toInt() ?? 0,
    column: (json['column'] as String?) ?? '',
    message: (json['message'] as String?) ?? 'Not accepted.',
  );

  @override
  String toString() => 'Row $row, $column: $message';
}

/// A workbook the server would not take.
///
/// Carries the rows rather than one message, because a roster of two
/// hundred with four bad emails needs those four pointed at.
class RosterImportRejected implements Exception {
  const RosterImportRejected(this.errors);

  final List<RosterRowError> errors;

  /// Reads the shape the server sends: a 422 whose detail is
  /// `{code: roster_import_invalid, errors: [...]}`.
  static RosterImportRejected? from(Object detail) {
    if (detail is! Map) return null;
    if (detail['code'] != 'roster_import_invalid') return null;

    final rows = detail['errors'];
    if (rows is! List) return null;

    return RosterImportRejected([
      for (final row in rows)
        if (row is Map)
          RosterRowError.fromJson(Map<String, dynamic>.from(row)),
    ]);
  }

  @override
  String toString() => errors.isEmpty
      ? 'The workbook was not accepted.'
      : '${errors.length} row${errors.length == 1 ? '' : 's'} need fixing.';
}

/// What a workbook put on the roster.
class RosterImportResult {
  const RosterImportResult({
    required this.filename,
    required this.insertedCount,
    required this.emails,
  });

  final String filename;
  final int insertedCount;

  /// The addresses that were added, for saying who is now able to
  /// register rather than only how many.
  final List<String> emails;

  factory RosterImportResult.fromJson(Map<String, dynamic> json) {
    final members = json['members'];
    return RosterImportResult(
      filename: (json['filename'] as String?) ?? '',
      insertedCount: (json['inserted_count'] as num?)?.toInt() ?? 0,
      emails: [
        if (members is List)
          for (final m in members)
            if (m is Map && m['email'] is String) m['email'] as String,
      ],
    );
  }
}

/// What the server will take as a roster workbook.
///
/// Checked before sending: a two-hundred-row file refused for its
/// extension has cost the upload for nothing.
abstract final class RosterWorkbook {
  static const int maxBytes = 5 * 1024 * 1024;

  /// The columns the server looks for, in the order it documents them.
  static const List<String> headers = [
    'Department',
    'Organization Full Name',
    'Full Name',
    'Email',
    'Role',
    'Position',
  ];

  /// Why this file would be refused, or null if it would be taken.
  static String? problemWith(String filename, int sizeBytes) {
    if (!filename.toLowerCase().endsWith('.xlsx')) {
      // Not .xls and not .csv: the server reads it with openpyxl.
      return 'The roster has to be an .xlsx workbook.';
    }
    if (sizeBytes <= 0) return 'That file is empty.';
    if (sizeBytes > maxBytes) return 'That workbook is over the 5 MB limit.';
    return null;
  }
}
