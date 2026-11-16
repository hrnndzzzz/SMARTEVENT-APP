import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/demo_data.dart';
import 'package:smartevent/widgets/report_charts.dart';

/// Six charts, defined once so the tile in the grid and the page it
/// opens cannot drift apart, and all drawn from the report itself.
void main() {
  final report = DemoData.financialReport();

  test('there are six of them, the trend first', () {
    final charts = ReportChart.all(report);
    expect(charts, hasLength(6));
    expect(charts.first.title, 'Over time');
  });

  test('each has a name and an explanation, and no two share a name', () {
    final charts = ReportChart.all(report);
    for (final chart in charts) {
      expect(chart.title.trim(), isNotEmpty);
      expect(chart.explanation.trim(), isNotEmpty);
    }
    expect({for (final c in charts) c.title}, hasLength(6));
  });

  test('they cover income as well as spending', () {
    final titles = ReportChart.all(report).map((c) => c.title.toLowerCase());
    expect(titles.join(' '), allOf(contains('came from'), contains('went')));
  });

  test('no report yet still defines six charts, with no figures', () {
    // Nothing loaded is a normal state, not a reason to show nothing.
    final charts = ReportChart.all(null);
    expect(charts, hasLength(6));
    expect(charts.every((c) => c.rows.isEmpty), isTrue);
  });

  test('each category row links to its ledger rows', () {
    final went = ReportChart.all(
      report,
    ).firstWhere((c) => c.title == 'Where it went');
    final catering = went.rows.firstWhere((r) => r.label == 'Catering');
    final matched = report.ledger.where(catering.filter!.matches);
    expect(matched, isNotEmpty);
    expect(
      matched.fold(0.0, (sum, r) => sum + r.amount),
      report.expensesByCategory
          .firstWhere((c) => c.categoryName == 'Catering')
          .totalExpenses,
    );
  });

  test('income sources are summed by type, largest first', () {
    final types = incomeByType(report.incomeBySource);
    expect(types.first.$2, greaterThanOrEqualTo(types.last.$2));
    expect(types.fold(0.0, (sum, t) => sum + t.$2), report.totalIncome);
  });

  test('proposals count every sent event, accepted and rejected', () {
    // Demo: 1 pending, 1 approved, 1 rejected, 2 drafts, 1 completed.
    final d = DemoData.dashboard();
    expect(d.proposedEventCount, 4);
    expect(d.acceptedEventCount, 2);
    expect(d.rejectedEventCount, 1);

    final proposals = ReportChart.all(
      report,
      dashboard: d,
      summary: DemoData.proposalSummary(),
    ).firstWhere((c) => c.title == 'Proposals');
    expect(proposals.rows.map((r) => r.value), ['4', '2', '1', '1']);
    expect(proposals.notes.map((n) => n.$2), [
      DemoData.proposalSummary().accepted,
      DemoData.proposalSummary().rejected,
    ]);
  });

  test('axis labels stay short', () {
    expect(compactPeso(950), '₱950');
    expect(compactPeso(2500), '₱2.5k');
    expect(compactPeso(14450), '₱14k');
    expect(compactPeso(1200000), '₱1.2M');
    expect(bucketLabel('2026-09'), 'Sep');
    expect(bucketLabel('2026-09-19'), '19');
    expect(bucketLabel('2026-09', long: true), 'Sep 2026');
  });
}
