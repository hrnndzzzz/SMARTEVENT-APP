import 'academic.dart';
import 'income.dart';

/// A single-call overview for the dashboard — `DashboardSummary`.
///
/// These are the server's figures. Nothing here may be recomputed from
/// whatever happens to be loaded on the client: a dashboard that adds up
/// the event cards currently on screen will disagree with the reports, and
/// the reports are right.
class DashboardSummary {
  final int totalCategories;
  final double totalAllocatedBudget;
  final double totalRemainingBudget;

  /// Counts keyed by the backend's own status strings. Both pending event
  /// stages appear separately, which is why this stays a map rather than
  /// being flattened into "pending".
  final Map<String, int> eventsByStatus;
  final Map<String, int> expensesByStatus;

  final int flaggedExpenseCount;
  final int lowStockItemCount;
  final int draftInventoryCount;

  DashboardSummary({
    required this.totalCategories,
    required this.totalAllocatedBudget,
    required this.totalRemainingBudget,
    required this.eventsByStatus,
    required this.expensesByStatus,
    required this.flaggedExpenseCount,
    required this.lowStockItemCount,
    required this.draftInventoryCount,
  });

  /// Allocation minus what the server says is left. Derived from two
  /// server figures rather than summed from expense rows.
  double get totalSpent => totalAllocatedBudget - totalRemainingBudget;

  int statusCount(Map<String, int> counts, List<String> keys) =>
      keys.fold(0, (sum, key) => sum + (counts[key] ?? 0));

  /// Events awaiting a decision at either stage.
  int get pendingEventCount =>
      statusCount(eventsByStatus, ['pending', 'pending_adviser', 'pending_admin']);

  int get pendingExpenseCount => expensesByStatus['pending'] ?? 0;

  static Map<String, int> _counts(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): (entry.value as num?)?.toInt() ?? 0,
    };
  }

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      totalCategories: (json['total_categories'] as num?)?.toInt() ?? 0,
      totalAllocatedBudget:
          (json['total_allocated_budget'] as num?)?.toDouble() ?? 0,
      totalRemainingBudget:
          (json['total_remaining_budget'] as num?)?.toDouble() ?? 0,
      eventsByStatus: _counts(json['events_by_status']),
      expensesByStatus: _counts(json['expenses_by_status']),
      flaggedExpenseCount: (json['flagged_expense_count'] as num?)?.toInt() ?? 0,
      lowStockItemCount: (json['low_stock_item_count'] as num?)?.toInt() ?? 0,
      draftInventoryCount:
          (json['draft_inventory_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One month of approved spending — `SpendingTrendPoint`.
///
/// Grouped by the expense's `created_at`, **not** its `expense_date`, so
/// these buckets will not always agree with a date-filtered financial
/// report. The chart has to say so rather than implying they match.
class SpendingTrendPoint {
  /// "YYYY-MM".
  final String month;
  final double totalAmount;
  final int expenseCount;

  SpendingTrendPoint({
    required this.month,
    required this.totalAmount,
    required this.expenseCount,
  });

  factory SpendingTrendPoint.fromJson(Map<String, dynamic> json) {
    return SpendingTrendPoint(
      month: json['month'] as String,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      expenseCount: (json['expense_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `CategoryReport` — one category's budget position.
class CategoryReport {
  final String categoryId;
  final String categoryName;
  final double allocatedBudget;
  final double remainingBudget;
  final double totalSpent;
  final int approvedExpenseCount;
  final int pendingExpenseCount;
  final int rejectedExpenseCount;

  CategoryReport({
    required this.categoryId,
    required this.categoryName,
    required this.allocatedBudget,
    required this.remainingBudget,
    required this.totalSpent,
    required this.approvedExpenseCount,
    required this.pendingExpenseCount,
    required this.rejectedExpenseCount,
  });

  factory CategoryReport.fromJson(Map<String, dynamic> json) {
    return CategoryReport(
      categoryId: json['category_id'] as String,
      categoryName: json['category_name'] as String,
      allocatedBudget: (json['allocated_budget'] as num?)?.toDouble() ?? 0,
      remainingBudget: (json['remaining_budget'] as num?)?.toDouble() ?? 0,
      totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0,
      approvedExpenseCount:
          (json['approved_expense_count'] as num?)?.toInt() ?? 0,
      pendingExpenseCount: (json['pending_expense_count'] as num?)?.toInt() ?? 0,
      rejectedExpenseCount:
          (json['rejected_expense_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Income grouped by where it came from — `IncomeSourceSummary`.
class IncomeSourceSummary {
  final FundSource sourceType;

  /// The actual payer's name, kept alongside the type.
  final String source;

  final int incomeCount;
  final double totalIncome;

  IncomeSourceSummary({
    required this.sourceType,
    required this.source,
    required this.incomeCount,
    required this.totalIncome,
  });

  factory IncomeSourceSummary.fromJson(Map<String, dynamic> json) {
    return IncomeSourceSummary(
      sourceType: fundSourceFromWire(json['source_type'] as String?),
      source: json['source'] as String? ?? '',
      incomeCount: (json['income_count'] as num?)?.toInt() ?? 0,
      totalIncome: (json['total_income'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One event's finances — `EventReport`, a liquidation-style summary.
///
/// [totalIncome] is eligible income only. Anything withheld pending a
/// receipt decision is reported separately and must stay separate.
class EventReport {
  final String eventId;
  final String title;
  final String status;

  final String? schoolYear;
  final Semester? semester;
  final EventScope? eventScope;

  final double estimatedCost;
  final double allocatedBudget;
  final double remainingBudget;

  /// Eligible income — excludes anything withheld.
  final double totalIncome;

  /// Approved spending only. Pending and rejected are not spending.
  final double totalSpent;

  final double netBalance;

  final List<IncomeSourceSummary> incomeBySource;
  final double withheldIncomeTotal;
  final int withheldIncomeCount;

  EventReport({
    required this.eventId,
    required this.title,
    required this.status,
    required this.schoolYear,
    required this.semester,
    required this.eventScope,
    required this.estimatedCost,
    required this.allocatedBudget,
    required this.remainingBudget,
    required this.totalIncome,
    required this.totalSpent,
    required this.netBalance,
    required this.incomeBySource,
    required this.withheldIncomeTotal,
    required this.withheldIncomeCount,
  });

  bool get hasWithheldIncome => withheldIncomeCount > 0;

  factory EventReport.fromJson(Map<String, dynamic> json) {
    return EventReport(
      eventId: json['event_id'] as String,
      title: json['title'] as String,
      status: json['status'] as String,
      schoolYear: json['school_year'] as String?,
      semester: semesterFromWire(json['semester'] as String?),
      eventScope: eventScopeFromWire(json['event_scope'] as String?),
      estimatedCost: (json['estimated_cost'] as num?)?.toDouble() ?? 0,
      allocatedBudget: (json['allocated_budget'] as num?)?.toDouble() ?? 0,
      remainingBudget: (json['remaining_budget'] as num?)?.toDouble() ?? 0,
      totalIncome: (json['total_income'] as num?)?.toDouble() ?? 0,
      totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0,
      netBalance: (json['net_balance'] as num?)?.toDouble() ?? 0,
      incomeBySource: [
        for (final s in (json['income_by_source'] as List? ?? const []))
          IncomeSourceSummary.fromJson((s as Map).cast<String, dynamic>()),
      ],
      withheldIncomeTotal:
          (json['withheld_income_total'] as num?)?.toDouble() ?? 0,
      withheldIncomeCount:
          (json['withheld_income_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One event's line in a consolidated report — `FinancialEventSummary`.
class FinancialEventSummary {
  final String eventId;
  final String title;
  final String? schoolYear;
  final Semester? semester;
  final EventScope? eventScope;
  final int incomeCount;
  final int expenseCount;
  final double totalIncome;
  final double totalExpenses;
  final double netBalance;
  final double withheldIncomeTotal;
  final int withheldIncomeCount;

  FinancialEventSummary({
    required this.eventId,
    required this.title,
    required this.schoolYear,
    required this.semester,
    required this.eventScope,
    required this.incomeCount,
    required this.expenseCount,
    required this.totalIncome,
    required this.totalExpenses,
    required this.netBalance,
    required this.withheldIncomeTotal,
    required this.withheldIncomeCount,
  });

  factory FinancialEventSummary.fromJson(Map<String, dynamic> json) {
    return FinancialEventSummary(
      eventId: json['event_id'] as String,
      title: json['title'] as String,
      schoolYear: json['school_year'] as String?,
      semester: semesterFromWire(json['semester'] as String?),
      eventScope: eventScopeFromWire(json['event_scope'] as String?),
      incomeCount: (json['income_count'] as num?)?.toInt() ?? 0,
      expenseCount: (json['expense_count'] as num?)?.toInt() ?? 0,
      totalIncome: (json['total_income'] as num?)?.toDouble() ?? 0,
      totalExpenses: (json['total_expenses'] as num?)?.toDouble() ?? 0,
      netBalance: (json['net_balance'] as num?)?.toDouble() ?? 0,
      withheldIncomeTotal:
          (json['withheld_income_total'] as num?)?.toDouble() ?? 0,
      withheldIncomeCount:
          (json['withheld_income_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `ConsolidatedFinancialReport` — a period's finances across events.
///
/// [unassignedExpenseTotal] is spending not tied to any event. It can
/// appear in unfiltered calendar totals but not in academic or event-scoped
/// ones, which is exactly why the report's own totals must be displayed
/// rather than recomputed from the event rows shown.
class ConsolidatedFinancialReport {
  final ReportPeriod period;

  /// The window the backend actually used. Displayed as returned, so the
  /// figures and the stated range always agree.
  final DateTime? startDate;
  final DateTime? endDate;

  final String? schoolYear;
  final Semester? semester;
  final EventScope? eventScope;

  final double totalIncome;
  final double totalExpenses;
  final double unassignedExpenseTotal;
  final double netBalance;

  final List<FinancialEventSummary> events;
  final List<IncomeSourceSummary> incomeBySource;
  final double withheldIncomeTotal;
  final int withheldIncomeCount;

  ConsolidatedFinancialReport({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.schoolYear,
    required this.semester,
    required this.eventScope,
    required this.totalIncome,
    required this.totalExpenses,
    required this.unassignedExpenseTotal,
    required this.netBalance,
    required this.events,
    required this.incomeBySource,
    required this.withheldIncomeTotal,
    required this.withheldIncomeCount,
  });

  bool get hasWithheldIncome => withheldIncomeCount > 0;
  bool get hasUnassignedSpending => unassignedExpenseTotal > 0;

  static DateTime? _date(Object? raw) =>
      raw == null ? null : DateTime.tryParse(raw as String);

  factory ConsolidatedFinancialReport.fromJson(Map<String, dynamic> json) {
    return ConsolidatedFinancialReport(
      period: reportPeriodFromWire(json['period'] as String?),
      startDate: _date(json['start_date']),
      endDate: _date(json['end_date']),
      schoolYear: json['school_year'] as String?,
      semester: semesterFromWire(json['semester'] as String?),
      eventScope: eventScopeFromWire(json['event_scope'] as String?),
      totalIncome: (json['total_income'] as num?)?.toDouble() ?? 0,
      totalExpenses: (json['total_expenses'] as num?)?.toDouble() ?? 0,
      unassignedExpenseTotal:
          (json['unassigned_expense_total'] as num?)?.toDouble() ?? 0,
      netBalance: (json['net_balance'] as num?)?.toDouble() ?? 0,
      events: [
        for (final e in (json['events'] as List? ?? const []))
          FinancialEventSummary.fromJson((e as Map).cast<String, dynamic>()),
      ],
      incomeBySource: [
        for (final s in (json['income_by_source'] as List? ?? const []))
          IncomeSourceSummary.fromJson((s as Map).cast<String, dynamic>()),
      ],
      withheldIncomeTotal:
          (json['withheld_income_total'] as num?)?.toDouble() ?? 0,
      withheldIncomeCount:
          (json['withheld_income_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The four reporting periods.
///
/// Two are calendar-based and filter on the dates money actually moved;
/// two are academic and filter on the event's own school-year labels. They
/// answer different questions and will not agree.
enum ReportPeriod { weekly, monthly, schoolYear, semester }

extension ReportPeriodInfo on ReportPeriod {
  String get wireName => switch (this) {
        ReportPeriod.weekly => 'weekly',
        ReportPeriod.monthly => 'monthly',
        ReportPeriod.schoolYear => 'school_year',
        ReportPeriod.semester => 'semester',
      };

  String get label => switch (this) {
        ReportPeriod.weekly => 'Weekly',
        ReportPeriod.monthly => 'Monthly',
        ReportPeriod.schoolYear => 'School year',
        ReportPeriod.semester => 'Semester',
      };

  /// Calendar periods filter on income received dates and expense dates —
  /// not on when the event happened.
  bool get isCalendar =>
      this == ReportPeriod.weekly || this == ReportPeriod.monthly;

  bool get needsSchoolYear =>
      this == ReportPeriod.schoolYear || this == ReportPeriod.semester;

  bool get needsSemester => this == ReportPeriod.semester;

  /// Whether a reference date is meaningful for this period.
  bool get usesReferenceDate => isCalendar;

  String get explanation => switch (this) {
        ReportPeriod.weekly =>
          'The Monday to Sunday week containing the reference date, by when '
              'money moved.',
        ReportPeriod.monthly =>
          'The calendar month containing the reference date, by when money '
              'moved.',
        ReportPeriod.schoolYear =>
          'Everything labelled with that school year on its event.',
        ReportPeriod.semester =>
          'Everything labelled with that school year and semester.',
      };
}

ReportPeriod reportPeriodFromWire(String? value) => switch (value) {
      'weekly' => ReportPeriod.weekly,
      'monthly' => ReportPeriod.monthly,
      'school_year' => ReportPeriod.schoolYear,
      'semester' => ReportPeriod.semester,
      _ => ReportPeriod.monthly,
    };

/// A suggested budget from past events — `BudgetRecommendation`.
///
/// Planned and actual are kept apart on purpose: what events budgeted and
/// what they spent usually differ, and blending them hides that.
class BudgetRecommendation {
  final String categoryId;
  final int sampleSize;
  final double? avgAllocatedBudget;
  final double? avgActualSpend;
  final String note;

  BudgetRecommendation({
    required this.categoryId,
    required this.sampleSize,
    required this.avgAllocatedBudget,
    required this.avgActualSpend,
    required this.note,
  });

  /// Nothing to base a suggestion on. The UI must say so rather than
  /// showing a confident zero.
  bool get hasEnoughData =>
      sampleSize > 0 && (avgAllocatedBudget != null || avgActualSpend != null);

  factory BudgetRecommendation.fromJson(Map<String, dynamic> json) {
    return BudgetRecommendation(
      categoryId: json['category_id'] as String,
      sampleSize: (json['sample_size'] as num?)?.toInt() ?? 0,
      avgAllocatedBudget: (json['avg_allocated_budget'] as num?)?.toDouble(),
      avgActualSpend: (json['avg_actual_spend'] as num?)?.toDouble(),
      note: json['note'] as String? ?? '',
    );
  }
}

/// Formats an export can be produced in.
enum ExportFormat { pdf, csv, html }

extension ExportFormatInfo on ExportFormat {
  String get wireName => name;

  String get label => switch (this) {
        ExportFormat.pdf => 'PDF',
        ExportFormat.csv => 'CSV',
        ExportFormat.html => 'Print-ready HTML',
      };

  /// What the response should actually carry. A body of any other type —
  /// a JSON error, most likely — must never be saved under this format's
  /// extension.
  String get expectedContentType => switch (this) {
        ExportFormat.pdf => 'application/pdf',
        ExportFormat.csv => 'text/csv',
        ExportFormat.html => 'text/html',
      };
}
