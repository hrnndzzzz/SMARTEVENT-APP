import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/reports.dart';
import 'package:smartevent/state/demo_data.dart';

/// The period chips used to move their own highlight and nothing else.
///
/// `_runLoad` returns early in demo mode without calling the loader,
/// which is right for anything that would hit the network — but it left
/// School year, Semester, Monthly and Weekly inert in the one screen
/// whose entire job is filtering, and in the mode the demo video is
/// recorded in.
void main() {
  // A Tuesday, mid-month, mid-first-semester: every window has room
  // both before and after it, so nothing passes by sitting on an edge.
  final on = DateTime(2026, 11, 17);

  ConsolidatedFinancialReport reportFor(ReportPeriod period) =>
      DemoData.financialReport(period: period, now: on);

  double counted(ConsolidatedFinancialReport r, {required bool income}) => r
      .ledger
      .where((e) => e.counted && e.isIncome == income)
      .fold<double>(0, (s, e) => s + e.amount);

  test('each period covers a different stretch, and they nest', () {
    final weekly = reportFor(ReportPeriod.weekly).ledger.length;
    final monthly = reportFor(ReportPeriod.monthly).ledger.length;
    final semester = reportFor(ReportPeriod.semester).ledger.length;
    final year = reportFor(ReportPeriod.schoolYear).ledger.length;

    expect(weekly, greaterThan(0), reason: 'the weekly chip shows nothing');
    expect(monthly, greaterThan(weekly));
    expect(semester, greaterThan(monthly));
    expect(year, greaterThanOrEqualTo(semester));
  });

  test('the totals are counted off the rows, not written beside them', () {
    // The fault this guards: the figures used to be hand-written to
    // agree with a fixed ledger, so the moment the ledger was filtered
    // the totals described rows that were no longer there.
    for (final period in ReportPeriod.values) {
      final r = reportFor(period);
      expect(
        r.totalIncome,
        counted(r, income: true),
        reason: '${period.label}: income disagrees with its own ledger',
      );
      expect(
        r.totalExpenses,
        counted(r, income: false),
        reason: '${period.label}: spending disagrees with its own ledger',
      );
      expect(r.netBalance, r.totalIncome - r.totalExpenses);
    }
  });

  test('every row it reports falls inside the window it claims', () {
    for (final period in ReportPeriod.values) {
      final r = reportFor(period);
      for (final row in r.ledger) {
        expect(
          row.occurredOn.isBefore(r.startDate!) ||
              row.occurredOn.isAfter(r.endDate!),
          isFalse,
          reason: '${period.label} lists ${row.description} from outside it',
        );
      }
    }
  });

  test('the weekly window is the week the day is in', () {
    final (from, to) = DemoData.reportWindow(ReportPeriod.weekly, on);
    expect(from, DateTime(2026, 11, 16), reason: 'Monday');
    expect(to, DateTime(2026, 11, 22), reason: 'Sunday');
  });

  test('and the school year runs June to May', () {
    final (from, to) = DemoData.reportWindow(ReportPeriod.schoolYear, on);
    expect(from, DateTime(2026, 6));
    expect(to, DateTime(2027, 5, 31));

    // January is the back half of the year that started last June.
    final (early, _) = DemoData.reportWindow(
      ReportPeriod.schoolYear,
      DateTime(2027, 1, 12),
    );
    expect(early, DateTime(2026, 6));
  });

  test('the weekly chip has something to show on any day of the week', () {
    // A demo whose filter lands on an empty report demonstrates
    // nothing, and the seeded rows are dated against today for exactly
    // this reason.
    for (var i = 0; i < 7; i++) {
      final day = DateTime(2026, 11, 16).add(Duration(days: i));
      final r = DemoData.financialReport(period: ReportPeriod.weekly, now: day);
      expect(
        r.ledger,
        isNotEmpty,
        reason: 'nothing to show on ${day.toIso8601String()}',
      );
    }
  });
}
