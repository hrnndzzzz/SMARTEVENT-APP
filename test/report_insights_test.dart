import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/income.dart';
import 'package:smartevent/api/models/reports.dart';
import 'package:smartevent/state/demo_data.dart';
import 'package:smartevent/state/report_insights.dart';

/// "Worth knowing": one rule each, worked out from the report alone.
void main() {
  FinancialEventSummary event({
    String title = 'Event',
    double income = 0,
    double spent = 0,
    double budget = 0,
    double spentToDate = 0,
    String status = 'approved',
  }) => FinancialEventSummary(
    eventId: title,
    title: title,
    schoolYear: null,
    semester: null,
    eventScope: null,
    incomeCount: 0,
    expenseCount: 0,
    totalIncome: income,
    totalExpenses: spent,
    netBalance: income - spent,
    withheldIncomeTotal: 0,
    withheldIncomeCount: 0,
    status: status,
    allocatedBudget: budget,
    spentToDate: spentToDate,
  );

  ConsolidatedFinancialReport report({
    List<FinancialEventSummary> events = const [],
    double income = 0,
    double spent = 0,
    List<CategorySpend> categories = const [],
    List<IncomeSourceSummary> sources = const [],
    double withheld = 0,
    double unassigned = 0,
    PeriodTotals? previous,
  }) => ConsolidatedFinancialReport(
    period: ReportPeriod.monthly,
    startDate: null,
    endDate: null,
    schoolYear: null,
    semester: null,
    eventScope: null,
    totalIncome: income,
    totalExpenses: spent,
    unassignedExpenseTotal: unassigned,
    netBalance: income - spent,
    events: events,
    incomeBySource: sources,
    withheldIncomeTotal: withheld,
    withheldIncomeCount: withheld > 0 ? 1 : 0,
    expensesByCategory: categories,
    previous: previous,
  );

  List<String> texts(ConsolidatedFinancialReport r) =>
      reportInsights(r).map((i) => i.text).toList();

  test('an empty report says nothing', () {
    expect(reportInsights(report()), isEmpty);
  });

  test('one event over budget is named, with amount and share', () {
    final found = reportInsights(
      report(events: [event(title: 'Fair', budget: 1000, spentToDate: 1100)]),
    );
    expect(found.single.warning, isTrue);
    expect(found.single.text, contains('Fair is over budget by ₱100 (10%)'));
  });

  test('several over budget are counted together', () {
    final found = texts(
      report(
        events: [
          event(title: 'A', budget: 100, spentToDate: 150),
          event(title: 'B', budget: 100, spentToDate: 120),
        ],
      ),
    );
    expect(found.first, contains('2 events are over budget, by ₱70'));
  });

  test('an event that spent more than it took in is pointed out', () {
    expect(
      texts(report(events: [event(title: 'Gala', income: 50, spent: 80)])),
      contains(contains('Gala spent more than it took in')),
    );
  });

  test('a dominant spending category is named past 40%', () {
    CategorySpend c(String name, double total) => CategorySpend(
      categoryId: name,
      categoryName: name,
      expenseCount: 1,
      totalExpenses: total,
    );
    expect(
      texts(report(spent: 100, categories: [c('Food', 45), c('Venue', 55)])),
      contains('Venue is 55% of all spending.'),
    );
    expect(
      texts(report(spent: 100, categories: [c('Food', 40), c('Venue', 30)])),
      isEmpty,
    );
  });

  test('a dominant income source is named past 50%', () {
    final found = texts(
      report(
        income: 100,
        sources: [
          IncomeSourceSummary(
            sourceType: FundSource.sponsorship,
            source: 'A',
            incomeCount: 1,
            totalIncome: 60,
          ),
          IncomeSourceSummary(
            sourceType: FundSource.donation,
            source: 'B',
            incomeCount: 1,
            totalIncome: 40,
          ),
        ],
      ),
    );
    expect(found, contains('60% of income comes from sponsorship.'));
  });

  test('a swing of 10% or more against the period before is reported', () {
    PeriodTotals before(double spent) =>
        PeriodTotals(totalIncome: 0, totalExpenses: spent, netBalance: -spent);
    expect(
      texts(report(spent: 120, previous: before(100))),
      contains(startsWith('Spending is up 20%')),
    );
    expect(
      texts(report(spent: 80, previous: before(100))),
      contains(startsWith('Spending is down 20%')),
    );
    expect(texts(report(spent: 105, previous: before(100))), isEmpty);
  });

  test('withheld income and unlinked spending are both said', () {
    final found = reportInsights(report(withheld: 250, unassigned: 40));
    expect(found.first.warning, isTrue);
    expect(found.first.text, contains('₱250 of income'));
    expect(found.last.text, contains('₱40 of spending is not linked'));
  });

  test('the demo report has something to say', () {
    expect(reportInsights(DemoData.financialReport()), isNotEmpty);
  });

  test('variance reads as under or over the event budget', () {
    expect(varianceLabel(event(budget: 1000, spentToDate: 900)), 'Under ₱100');
    expect(
      varianceLabel(event(budget: 1000, spentToDate: 1040)),
      'Over ₱40 (4%)',
    );
    expect(varianceLabel(event()), 'No budget set');
  });

  test('a ledger filter narrows by kind, event, category and source', () {
    final rows = DemoData.financialReport().ledger;
    expect(rows.where(LedgerFilter.all.matches), hasLength(rows.length));
    expect(
      rows.where(const LedgerFilter(income: true).matches).every((r) => r.isIncome),
      isTrue,
    );
    expect(
      rows
          .where(const LedgerFilter(eventId: 'demo-ev-1').matches)
          .every((r) => r.eventId == 'demo-ev-1'),
      isTrue,
    );
    final marketing = rows.where(
      const LedgerFilter(income: false, category: 'Marketing').matches,
    );
    expect(marketing.fold(0.0, (s, r) => s + r.amount), 1500);
    expect(
      rows.where(
        const LedgerFilter(sourceType: FundSource.sponsorship).matches,
      ),
      hasLength(2),
    );
  });
}
