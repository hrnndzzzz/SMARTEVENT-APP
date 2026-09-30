import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/academic.dart';
import 'package:smartevent/api/models/reports.dart';
import 'package:smartevent/api/reports_service.dart';

/// Reports are what gets printed and defended, so the rules about which
/// filters a period needs — and which totals may not be recomputed — matter
/// more here than anywhere else.
void main() {
  group('period requirements', () {
    test('calendar periods need neither a school year nor a semester', () {
      for (final period in [ReportPeriod.weekly, ReportPeriod.monthly]) {
        expect(period.isCalendar, isTrue, reason: period.name);
        expect(period.needsSchoolYear, isFalse, reason: period.name);
        expect(period.needsSemester, isFalse, reason: period.name);
        expect(
          ReportsService.validateFinancialRequest(period: period),
          isNull,
          reason: period.name,
        );
      }
    });

    test('a school-year report requires a school year', () {
      expect(
        ReportsService.validateFinancialRequest(period: ReportPeriod.schoolYear),
        contains('school year'),
      );
      expect(
        ReportsService.validateFinancialRequest(
          period: ReportPeriod.schoolYear,
          schoolYear: '2026-2027',
        ),
        isNull,
      );
    });

    test('a semester report requires both', () {
      expect(
        ReportsService.validateFinancialRequest(
          period: ReportPeriod.semester,
          schoolYear: '2026-2027',
        ),
        contains('semester'),
      );
      expect(
        ReportsService.validateFinancialRequest(
          period: ReportPeriod.semester,
          schoolYear: '2026-2027',
          semester: Semester.first,
        ),
        isNull,
      );
    });

    test('an invalid school year is caught before the request', () {
      // The backend answers 422; catching it here explains why.
      expect(
        ReportsService.validateFinancialRequest(
          period: ReportPeriod.schoolYear,
          schoolYear: '2026-2028',
        ),
        contains('consecutive'),
      );
    });

    test('only calendar periods use a reference date', () {
      expect(ReportPeriod.weekly.usesReferenceDate, isTrue);
      expect(ReportPeriod.monthly.usesReferenceDate, isTrue);
      expect(ReportPeriod.schoolYear.usesReferenceDate, isFalse);
      expect(ReportPeriod.semester.usesReferenceDate, isFalse);
    });

    test('every period explains what it filters on', () {
      for (final period in ReportPeriod.values) {
        expect(period.explanation, isNotEmpty, reason: period.name);
      }
      // Calendar periods filter on when money moved, not when events ran.
      expect(ReportPeriod.weekly.explanation, contains('money moved'));
      expect(ReportPeriod.schoolYear.explanation, contains('labelled'));
    });

    test('round-trips every period', () {
      for (final period in ReportPeriod.values) {
        expect(reportPeriodFromWire(period.wireName), period);
      }
      expect(ReportPeriod.schoolYear.wireName, 'school_year');
    });
  });

  group('consolidated report totals', () {
    ConsolidatedFinancialReport report({
      double income = 1000,
      double expenses = 400,
      double unassigned = 0,
      double withheld = 0,
      int withheldCount = 0,
      List<Map<String, dynamic>> events = const [],
    }) {
      return ConsolidatedFinancialReport.fromJson({
        'period': 'monthly',
        'start_date': '2026-09-01',
        'end_date': '2026-09-30',
        'school_year': null,
        'semester': null,
        'event_scope': null,
        'total_income': income,
        'total_expenses': expenses,
        'unassigned_expense_total': unassigned,
        'net_balance': income - expenses,
        'events': events,
        'income_by_source': const [],
        'withheld_income_total': withheld,
        'withheld_income_count': withheldCount,
      });
    }

    test('keeps the window the backend used', () {
      final r = report();
      expect(r.startDate, DateTime(2026, 9, 1));
      expect(r.endDate, DateTime(2026, 9, 30));
    });

    test('flags withheld income separately from the total', () {
      final r = report(income: 1000, withheld: 250, withheldCount: 2);
      expect(r.hasWithheldIncome, isTrue);
      // The withheld amount is NOT part of total_income.
      expect(r.totalIncome, 1000);
      expect(r.withheldIncomeTotal, 250);
    });

    test('flags spending not tied to any event', () {
      // This is why the event rows need not add up to the totals.
      final r = report(expenses: 400, unassigned: 150);
      expect(r.hasUnassignedSpending, isTrue);
      expect(r.unassignedExpenseTotal, 150);
    });

    test('event rows can legitimately not sum to the total', () {
      final r = report(
        expenses: 400,
        unassigned: 150,
        events: [
          {
            'event_id': 'e1',
            'title': 'Summit',
            'school_year': '2026-2027',
            'semester': '1st',
            'event_scope': 'departmental',
            'income_count': 1,
            'expense_count': 1,
            'total_income': 500,
            'total_expenses': 250,
            'net_balance': 250,
            'withheld_income_total': 0,
            'withheld_income_count': 0,
          }
        ],
      );

      final rowSum =
          r.events.fold<double>(0, (sum, e) => sum + e.totalExpenses);
      expect(rowSum, 250);
      expect(r.totalExpenses, 400);
      // The difference is the unassigned spending, which belongs to no
      // event — so a UI that summed the rows would understate it.
      expect(r.totalExpenses - rowSum, r.unassignedExpenseTotal);
    });
  });

  group('budget recommendation', () {
    BudgetRecommendation rec({int sample = 3, double? allocated, double? spend}) {
      return BudgetRecommendation.fromJson({
        'category_id': 'c1',
        'sample_size': sample,
        'avg_allocated_budget': allocated,
        'avg_actual_spend': spend,
        'note': 'Based on past events.',
      });
    }

    test('knows when there is nothing to base a suggestion on', () {
      expect(rec(sample: 0).hasEnoughData, isFalse);
      expect(rec(sample: 3).hasEnoughData, isFalse,
          reason: 'a sample with no averages is still nothing to go on');
      expect(rec(sample: 3, allocated: 5000).hasEnoughData, isTrue);
    });

    test('keeps planned and actual apart', () {
      final r = rec(sample: 4, allocated: 5000, spend: 3800);
      // Blending these would hide that events routinely overbudget.
      expect(r.avgAllocatedBudget, 5000);
      expect(r.avgActualSpend, 3800);
    });
  });

  group('export formats', () {
    test('each format expects its own content type', () {
      expect(ExportFormat.pdf.expectedContentType, 'application/pdf');
      expect(ExportFormat.csv.expectedContentType, 'text/csv');
      expect(ExportFormat.html.expectedContentType, 'text/html');
    });

    test('no format expects JSON', () {
      // A JSON body means an error, and must never be saved as a report.
      for (final format in ExportFormat.values) {
        expect(format.expectedContentType, isNot(contains('json')));
      }
    });
  });

  group('dashboard summary', () {
    test('derives spend from the two server figures, not from rows', () {
      final summary = DashboardSummary.fromJson({
        'total_categories': 4,
        'total_allocated_budget': 10000,
        'total_remaining_budget': 6500,
        'events_by_status': {'pending_adviser': 2, 'pending_admin': 1, 'approved': 5},
        'expenses_by_status': {'pending': 3, 'approved': 7},
        'flagged_expense_count': 1,
        'low_stock_item_count': 2,
        'draft_inventory_count': 0,
      });

      expect(summary.totalSpent, 3500);
      // Both pending stages count, and stay visible separately.
      expect(summary.pendingEventCount, 3);
      expect(summary.eventsByStatus['pending_adviser'], 2);
      expect(summary.eventsByStatus['pending_admin'], 1);
      expect(summary.pendingExpenseCount, 3);
    });

    test('tolerates a missing or empty payload', () {
      final summary = DashboardSummary.fromJson({});
      expect(summary.totalCategories, 0);
      expect(summary.eventsByStatus, isEmpty);
      expect(summary.pendingEventCount, 0);
    });
  });
}
