import 'api_client.dart';
import 'models/academic.dart';
import 'models/remote_expense.dart';
import 'models/reports.dart';

/// Dashboard analytics, financial reports and their exports.
///
/// Every figure here comes from the server. Nothing is recomputed from
/// whatever the client happens to have loaded — a dashboard that sums the
/// cards on screen will disagree with the reports, and the reports are the
/// ones that get printed.
class ReportsService {
  final ApiClient _client;
  ReportsService(this._client);

  Future<DashboardSummary> dashboard() async {
    final response = await _client.get('/analytics/dashboard');
    return DashboardSummary.fromJson(response as Map<String, dynamic>);
  }

  /// Approved-expense totals by month. Grouped by `created_at`, so label
  /// it as "recorded" rather than implying it matches a date-filtered
  /// report.
  Future<List<SpendingTrendPoint>> spendingTrends({int months = 6}) async {
    final response = await _client.get(
      '/analytics/spending-trends',
      query: {'months': months.toString()},
    );
    return (response as List)
        .map((json) => SpendingTrendPoint.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Expenses the backend has flagged.
  ///
  /// The route is called "threats", which is not the label to put on
  /// screen: a flag means something looked unusual enough to check, not
  /// that anyone did anything wrong.
  Future<List<RemoteExpense>> flagged() async {
    final response = await _client.get('/analytics/threats');
    return (response as List)
        .map((json) => RemoteExpense.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<CategoryReport> categoryReport(String categoryId) async {
    final response = await _client.get('/reports/category/$categoryId');
    return CategoryReport.fromJson(response as Map<String, dynamic>);
  }

  Future<EventReport> eventReport(String eventId) async {
    final response = await _client.get('/reports/event/$eventId');
    return EventReport.fromJson(response as Map<String, dynamic>);
  }

  /// `GET /reports/financial`.
  ///
  /// School year is required for school-year and semester periods, and
  /// semester additionally for the latter — the backend answers 422
  /// otherwise, so the caller should check first.
  Future<ConsolidatedFinancialReport> financialReport({
    required ReportPeriod period,
    DateTime? referenceDate,
    String? schoolYear,
    Semester? semester,
    EventScope? eventScope,
  }) async {
    final response = await _client.get(
      '/reports/financial',
      query: _financialQuery(
        period: period,
        referenceDate: referenceDate,
        schoolYear: schoolYear,
        semester: semester,
        eventScope: eventScope,
      ),
    );
    return ConsolidatedFinancialReport.fromJson(
        response as Map<String, dynamic>);
  }

  Future<BudgetRecommendation> budgetRecommendation(String categoryId) async {
    final response = await _client.get(
      '/recommendations/event-budget',
      query: {'category_id': categoryId},
    );
    return BudgetRecommendation.fromJson(response as Map<String, dynamic>);
  }

  // ---- Exports -----------------------------------------------------------

  Future<DownloadedFile> exportDashboard(ExportFormat format) {
    return _client.download(
      '/reports/dashboard/export',
      query: {'format': format.wireName},
      expectedContentType: format.expectedContentType,
      fallbackFilename: 'dashboard.${format.wireName}',
    );
  }

  Future<DownloadedFile> exportEvent(String eventId, ExportFormat format) {
    return _client.download(
      '/reports/event/$eventId/export',
      query: {'format': format.wireName},
      expectedContentType: format.expectedContentType,
      fallbackFilename: 'event-report.${format.wireName}',
    );
  }

  Future<DownloadedFile> exportCategory(String categoryId, ExportFormat format) {
    return _client.download(
      '/reports/category/$categoryId/export',
      query: {'format': format.wireName},
      expectedContentType: format.expectedContentType,
      fallbackFilename: 'category-report.${format.wireName}',
    );
  }

  /// The export must use the same filters as the report on screen, so it
  /// takes the identical arguments rather than re-deriving them.
  Future<DownloadedFile> exportFinancial({
    required ReportPeriod period,
    required ExportFormat format,
    DateTime? referenceDate,
    String? schoolYear,
    Semester? semester,
    EventScope? eventScope,
  }) {
    return _client.download(
      '/reports/financial/export',
      query: {
        ..._financialQuery(
          period: period,
          referenceDate: referenceDate,
          schoolYear: schoolYear,
          semester: semester,
          eventScope: eventScope,
        ),
        'format': format.wireName,
      },
      expectedContentType: format.expectedContentType,
      fallbackFilename: 'financial-report.${format.wireName}',
    );
  }

  /// Shared so the report and its export can never be built from different
  /// filters — the exported figures must match what was displayed.
  static Map<String, String> _financialQuery({
    required ReportPeriod period,
    DateTime? referenceDate,
    String? schoolYear,
    Semester? semester,
    EventScope? eventScope,
  }) {
    return {
      'period': period.wireName,
      if (referenceDate != null)
        'reference_date': referenceDate.toIso8601String().split('T').first,
      if (schoolYear != null) 'school_year': schoolYear,
      if (semester != null) 'semester': semester.wireName,
      if (eventScope != null) 'event_scope': eventScope.wireName,
    };
  }

  /// Checks a report request before sending it, so a missing school year is
  /// explained rather than coming back as a 422.
  static String? validateFinancialRequest({
    required ReportPeriod period,
    String? schoolYear,
    Semester? semester,
  }) {
    if (period.needsSchoolYear) {
      if (schoolYear == null || schoolYear.isEmpty) {
        return 'Choose a school year for a ${period.label.toLowerCase()} report.';
      }
      if (!SchoolYear.isValid(schoolYear)) {
        return 'A school year must be two consecutive years, like 2026-2027.';
      }
    }
    if (period.needsSemester && semester == null) {
      return 'Choose a semester for a semester report.';
    }
    return null;
  }
}
