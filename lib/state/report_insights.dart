import '../api/models/income.dart';
import '../api/models/reports.dart';
import '../theme/peso.dart';

/// One line in the "Worth knowing" card.
class ReportInsight {
  const ReportInsight(this.text, {this.warning = false});

  final String text;

  /// Something to act on, rather than something to know.
  final bool warning;
}

/// The handful of things a treasurer would point out reading this report.
///
/// Worked out from the report alone, so it always agrees with the figures
/// on screen. Warnings come first.
List<ReportInsight> reportInsights(ConsolidatedFinancialReport report) {
  final warnings = <ReportInsight>[];
  final notes = <ReportInsight>[];

  final over = report.events.where((e) => e.isOverBudget).toList();
  if (over.length == 1) {
    final e = over.single;
    warnings.add(ReportInsight(
      '${e.title} is over budget by ${peso(-e.variance, decimals: 0)} '
      '(${_percent(-e.variance / e.allocatedBudget)}).',
      warning: true,
    ));
  } else if (over.length > 1) {
    final total = over.fold(0.0, (sum, e) => sum - e.variance);
    warnings.add(ReportInsight(
      '${over.length} events are over budget, by ${peso(total, decimals: 0)} '
      'between them.',
      warning: true,
    ));
  }

  final shortfall = report.events
      .where((e) => e.totalExpenses > 0 && e.totalExpenses > e.totalIncome)
      .toList();
  if (shortfall.isNotEmpty) {
    final names = shortfall.length <= 2
        ? shortfall.map((e) => e.title).join(' and ')
        : '${shortfall.length} events';
    notes.add(ReportInsight(
      '$names spent more than ${shortfall.length == 1 ? 'it' : 'they'} '
      'took in this period.',
    ));
  }

  if (report.hasWithheldIncome) {
    warnings.add(ReportInsight(
      '${peso(report.withheldIncomeTotal, decimals: 0)} of income '
      '(${report.withheldIncomeCount} '
      '${report.withheldIncomeCount == 1 ? 'entry' : 'entries'}) is held out '
      'of the totals pending a receipt decision.',
      warning: true,
    ));
  }

  if (report.hasUnassignedSpending) {
    notes.add(ReportInsight(
      '${peso(report.unassignedExpenseTotal, decimals: 0)} of spending is not '
      'linked to any event.',
    ));
  }

  if (report.totalExpenses > 0 && report.expensesByCategory.isNotEmpty) {
    final top = report.expensesByCategory.reduce(
      (a, b) => a.totalExpenses >= b.totalExpenses ? a : b,
    );
    final share = top.totalExpenses / report.totalExpenses;
    if (share > 0.4) {
      notes.add(ReportInsight(
        '${top.categoryName} is ${_percent(share)} of all spending.',
      ));
    }
  }

  if (report.totalIncome > 0) {
    final byType = <FundSource, double>{};
    for (final s in report.incomeBySource) {
      byType[s.sourceType] = (byType[s.sourceType] ?? 0) + s.totalIncome;
    }
    if (byType.isNotEmpty) {
      final top = byType.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final share = top.value / report.totalIncome;
      if (share > 0.5) {
        notes.add(ReportInsight(
          '${_percent(share)} of income comes from '
          '${top.key.label.toLowerCase()}.',
        ));
      }
    }
  }

  final before = report.previous?.totalExpenses ?? 0;
  if (before > 0) {
    final change = (report.totalExpenses - before) / before;
    if (change.abs() >= 0.1) {
      notes.add(ReportInsight(
        'Spending is ${change > 0 ? 'up' : 'down'} ${_percent(change.abs())} '
        'on the period before, from ${peso(before, decimals: 0)} to '
        '${peso(report.totalExpenses, decimals: 0)}.',
      ));
    }
  }

  return [...warnings, ...notes];
}

String _percent(double ratio) => '${(ratio * 100).round()}%';

/// "Under ₱1,100" or "Over ₱950 (9%)", against the event's own budget.
String varianceLabel(FinancialEventSummary event) {
  if (event.allocatedBudget <= 0) return 'No budget set';
  if (event.isOverBudget) {
    return 'Over ${peso(-event.variance, decimals: 0)} '
        '(${_percent(-event.variance / event.allocatedBudget)})';
  }
  return 'Under ${peso(event.variance, decimals: 0)}';
}

/// Which ledger rows to show. Every field left null matches anything.
class LedgerFilter {
  const LedgerFilter({
    this.income,
    this.eventId,
    this.category,
    this.sourceType,
    this.title,
  });

  /// True for income only, false for spending only.
  final bool? income;
  final String? eventId;

  /// An expense category's name, as the ledger labels it.
  final String? category;
  final FundSource? sourceType;

  /// What the filter is called on its chip, when it is narrower than a kind.
  final String? title;

  static const all = LedgerFilter();

  bool matches(LedgerEntry entry) =>
      (income == null || entry.isIncome == income) &&
      (eventId == null || entry.eventId == eventId) &&
      (category == null || (!entry.isIncome && entry.label == category)) &&
      (sourceType == null || entry.sourceType == sourceType);
}
