import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/income.dart';
import 'package:smartevent/api/models/reports.dart';
import 'package:smartevent/widgets/report_charts.dart';

/// Four charts, defined once so the tile in the grid and the page it
/// opens cannot drift apart.
void main() {
  List<ReportChart> charts({
    Map<String, double> budgets = const {'Venue': 100},
    Map<String, double> spend = const {'Venue': 40},
    List<IncomeSourceSummary> sources = const [],
    List<FinancialEventSummary> events = const [],
  }) => ReportChart.all(
    budgets: budgets,
    spend: spend,
    sources: sources,
    events: events,
  );

  test('there are four of them', () {
    expect(charts(), hasLength(4));
  });

  test('each has a name and an explanation', () {
    for (final chart in charts()) {
      expect(chart.title.trim(), isNotEmpty);
      expect(chart.explanation.trim(), isNotEmpty);
    }
  });

  test('no two share a name', () {
    expect({for (final c in charts()) c.title}, hasLength(4));
  });

  test('they cover income as well as spending', () {
    final titles = charts().map((c) => c.title.toLowerCase()).join(' ');
    expect(titles, contains('came from'));
    expect(titles, contains('went'));
  });

  test('an empty period still defines four charts', () {
    // Nothing recorded is a normal state, not a reason to show nothing.
    expect(charts(budgets: const {}, spend: const {}), hasLength(4));
  });
}
