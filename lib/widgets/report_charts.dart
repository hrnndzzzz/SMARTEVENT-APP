import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api/models/income.dart';
import '../api/models/reports.dart';
import '../state/report_insights.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import '../theme/peso.dart';

/// One exact figure behind a chart, listed under it on its own page.
class ChartRow {
  const ChartRow({
    required this.label,
    required this.value,
    this.detail,
    this.colour,
    this.filter,
  });

  final String label;
  final String value;
  final String? detail;
  final Color? colour;

  /// The ledger rows behind this figure, so tapping it can show them.
  final LedgerFilter? filter;
}

/// The charts the Analytics screen offers, each with a name and a builder.
///
/// Kept in one place so the tile and the full-screen page cannot drift
/// apart: they are the same chart, drawn at two sizes. Every figure comes
/// from the report, so changing the period or organization changes all of
/// them together.
class ReportChart {
  const ReportChart({
    required this.title,
    required this.explanation,
    required this.build,
    this.rows = const [],
    this.notes = const [],
    this.notesCaption,
  });

  final String title;
  final String explanation;

  /// [large] is the full-screen page: taller, with touch tooltips.
  final Widget Function(BuildContext context, bool large) build;
  final List<ChartRow> rows;

  /// Short readings under the chart on its own page, as (heading, text).
  final List<(String, String)> notes;

  /// Where [notes] came from, said under them.
  final String? notesCaption;

  /// The trend first: it is drawn full width above the others.
  ///
  /// The proposals chart counts events rather than money, so it reads
  /// [dashboard] instead of the report.
  static List<ReportChart> all(
    ConsolidatedFinancialReport? report, {
    DashboardSummary? dashboard,
    ProposalSummary? summary,
  }) {
    final events = report?.events ?? const <FinancialEventSummary>[];
    final budgeted = [
      for (final e in events)
        if (e.allocatedBudget > 0) e,
    ];
    final active = [
      for (final e in events)
        if (e.totalIncome > 0 || e.totalExpenses > 0) e,
    ];
    final categories = report?.expensesByCategory ?? const <CategorySpend>[];
    final sources = incomeByType(report?.incomeBySource ?? const []);
    final trend = report?.trend ?? const <ReportTrendPoint>[];

    return [
      ReportChart(
        title: 'Over time',
        explanation:
            'Income and approved spending by day for a week or month, and '
            'by month for a semester or school year.',
        build: (context, large) => TrendChart(points: trend, large: large),
        rows: [
          for (final p in trend.reversed)
            if (p.totalIncome > 0 || p.totalExpenses > 0)
              ChartRow(
                label: bucketLabel(p.bucket, long: true),
                value: peso(p.totalIncome - p.totalExpenses, decimals: 0),
                detail:
                    'In ${peso(p.totalIncome, decimals: 0)} · '
                    'out ${peso(p.totalExpenses, decimals: 0)}',
              ),
        ],
      ),
      ReportChart(
        title: 'Budget vs actual',
        explanation:
            "Each event's budget against everything it has spent so far, "
            'not only in this period. Coral is over budget.',
        build: (context, large) =>
            BudgetVsActualChart(events: budgeted, large: large),
        rows: [
          for (final e in budgeted)
            ChartRow(
              label: e.title,
              value: peso(e.spentToDate, decimals: 0),
              detail:
                  'Budget ${peso(e.allocatedBudget, decimals: 0)} · '
                  '${e.isCommitted ? varianceLabel(e) : 'Proposed'}',
              filter: LedgerFilter(eventId: e.eventId, title: e.title),
            ),
        ],
      ),
      ReportChart(
        title: 'In and out by event',
        explanation:
            'What each event took in against what it spent in this period.',
        build: (context, large) => InOutChart(events: active, large: large),
        rows: [
          for (final e in active)
            ChartRow(
              label: e.title,
              value: peso(e.netBalance, decimals: 0),
              detail:
                  'In ${peso(e.totalIncome, decimals: 0)} · '
                  'out ${peso(e.totalExpenses, decimals: 0)}',
              filter: LedgerFilter(eventId: e.eventId, title: e.title),
            ),
        ],
      ),
      ReportChart(
        title: 'Where it went',
        explanation: 'Approved spending split by budget category.',
        build: (context, large) => DonutChart(
          slices: [
            for (final (i, c) in categories.indexed)
              (c.categoryName, c.totalExpenses, sliceColour(i)),
          ],
          centre: 'Spent',
          empty: 'No approved spending in this period.',
          large: large,
        ),
        rows: [
          for (final (i, c) in categories.indexed)
            ChartRow(
              label: c.categoryName,
              value: peso(c.totalExpenses, decimals: 0),
              detail:
                  '${c.expenseCount} '
                  '${c.expenseCount == 1 ? 'expense' : 'expenses'}',
              colour: sliceColour(i),
              filter: LedgerFilter(
                income: false,
                category: c.categoryName,
                title: c.categoryName,
              ),
            ),
        ],
      ),
      ReportChart(
        title: 'Where it came from',
        explanation: 'Income by kind of source: fees, sponsorship, donations.',
        build: (context, large) => DonutChart(
          slices: [
            for (final (i, s) in sources.indexed)
              (s.$1.label, s.$2, sliceColour(i)),
          ],
          centre: 'Income',
          empty: 'No income in this period.',
          large: large,
        ),
        rows: [
          for (final (i, s) in sources.indexed)
            ChartRow(
              label: s.$1.label,
              value: peso(s.$2, decimals: 0),
              colour: sliceColour(i),
              filter: LedgerFilter(
                income: true,
                sourceType: s.$1,
                title: s.$1.label,
              ),
            ),
        ],
      ),
      ReportChart(
        title: 'Proposals',
        explanation:
            'Every event sent for review, and how many were accepted or '
            'rejected. Counts every event on record, not only this period.',
        build: (context, large) =>
            ProposalsChart(dashboard: dashboard, large: large),
        rows: [
          if (dashboard case final d?) ...[
            ChartRow(label: 'Proposed', value: '${d.proposedEventCount}'),
            ChartRow(label: 'Accepted', value: '${d.acceptedEventCount}'),
            ChartRow(label: 'Rejected', value: '${d.rejectedEventCount}'),
            ChartRow(
              label: 'Waiting',
              value:
                  '${d.proposedEventCount - d.acceptedEventCount - d.rejectedEventCount}',
              detail: 'Still in review',
            ),
          ],
        ],
        notes: [
          (
            'What gets proposals accepted',
            summary?.accepted ?? 'Not enough decisions to summarise yet.',
          ),
          (
            'What causes rejections',
            summary?.rejected ?? 'Not enough decisions to summarise yet.',
          ),
        ],
        notesCaption: "Written by AI from reviewers' remarks.",
      ),
    ];
  }
}

/// Proposed, accepted and rejected as three bars measured against the
/// proposed total.
class ProposalsChart extends StatelessWidget {
  const ProposalsChart({
    super.key,
    required this.dashboard,
    this.large = false,
  });

  final DashboardSummary? dashboard;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    if (d == null || d.proposedEventCount == 0) {
      return const _NoData(message: 'No proposal has been sent yet.');
    }
    final total = d.proposedEventCount;
    final bars = [
      ('Proposed', total, BrutTone.brand),
      ('Accepted', d.acceptedEventCount, BrutTone.mint),
      ('Rejected', d.rejectedEventCount, BrutTone.coral),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, count, tone) in bars) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppText.body.copyWith(fontSize: 12.5),
                ),
              ),
              Text('$count', style: AppText.number.copyWith(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          BrutProgressBar(
            value: count / total,
            tone: tone,
            height: large ? 18 : BrutProgressBar.thickness,
          ),
          SizedBox(height: large ? 14 : 10),
        ],
      ],
    );
  }
}

/// Income summed by source type, largest first.
List<(FundSource, double)> incomeByType(List<IncomeSourceSummary> sources) {
  final totals = <FundSource, double>{};
  for (final s in sources) {
    totals[s.sourceType] = (totals[s.sourceType] ?? 0) + s.totalIncome;
  }
  return [
    for (final e in totals.entries)
      if (e.value > 0) (e.key, e.value),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
}

Color sliceColour(int index) =>
    AppColors.accents[index % AppColors.accents.length];

/// "₱12k" for an axis, where the centavos are noise.
String compactPeso(num value) {
  final v = value.abs();
  final sign = value < 0 ? '-' : '';
  if (v >= 1000000) return '$sign₱${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) {
    return '$sign₱${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
  }
  return '$sign₱${v.round()}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Sep" or "19" on an axis; "September 2026" or "19 Sep 2026" in a list.
String bucketLabel(String bucket, {bool long = false}) {
  final parts = bucket.split('-').map(int.tryParse).toList();
  if (parts.length < 2 || parts.contains(null)) return bucket;
  final month = _months[(parts[1]! - 1).clamp(0, 11)];
  if (parts.length == 2) return long ? '$month ${parts[0]}' : month;
  return long ? '${parts[2]} $month ${parts[0]}' : '${parts[2]}';
}

TextStyle _axis(BuildContext context) =>
    AppText.caption.copyWith(fontSize: 9, color: context.palette.subtle);

FlTitlesData _titles(
  BuildContext context, {
  required Widget Function(int index, TitleMeta meta) bottom,
  double bottomSize = 22,
  double? interval,
}) {
  const none = AxisTitles(sideTitles: SideTitles(showTitles: false));
  return FlTitlesData(
    topTitles: none,
    rightTitles: none,
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 38,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(compactPeso(value), style: _axis(context)),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: bottomSize,
        interval: interval ?? 1,
        getTitlesWidget: (value, meta) =>
            SideTitleWidget(meta: meta, child: bottom(value.toInt(), meta)),
      ),
    ),
  );
}

FlGridData _grid(BuildContext context) => FlGridData(
  drawVerticalLine: false,
  getDrawingHorizontalLine: (_) =>
      FlLine(color: context.palette.line, strokeWidth: 1),
);

class _Series {
  const _Series(this.name, this.colour, this.values, {this.colourAt});

  final String name;
  final Color colour;
  final List<double> values;

  /// A different fill for one bar, such as coral where it is over budget.
  final Color Function(int index)? colourAt;
}

/// Bars side by side, one group per event.
class _GroupedBars extends StatelessWidget {
  const _GroupedBars({
    required this.labels,
    required this.series,
    required this.large,
    required this.empty,
    this.legend = const [],
  });

  final List<String> labels;
  final List<_Series> series;
  final bool large;
  final String empty;
  final List<Widget> legend;

  @override
  Widget build(BuildContext context) {
    final peak = series.expand((s) => s.values).fold(0.0, math.max);
    if (labels.isEmpty || peak <= 0) return _NoData(message: empty);

    final ink = context.palette.ink;
    final chart = BarChart(
      BarChartData(
        maxY: peak * 1.15,
        alignment: BarChartAlignment.spaceAround,
        gridData: _grid(context),
        borderData: FlBorderData(show: false),
        titlesData: _titles(
          context,
          bottomSize: 30,
          bottom: (i, meta) => i < 0 || i >= labels.length
              ? const SizedBox.shrink()
              : SizedBox(
                  width: 58,
                  child: Text(
                    labels[i],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: _axis(context),
                  ),
                ),
        ),
        barTouchData: BarTouchData(
          enabled: large,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => ink,
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
                  '${labels[groupIndex]}\n'
                  '${series[rodIndex].name}: ${peso(rod.toY, decimals: 0)}',
                  AppText.caption.copyWith(
                    fontSize: 11,
                    color: context.palette.surface,
                  ),
                ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < labels.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 3,
              barRods: [
                for (final s in series)
                  BarChartRodData(
                    toY: s.values[i],
                    color: s.colourAt?.call(i) ?? s.colour,
                    width: large ? 14 : 10,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                    borderSide: BorderSide(color: ink, width: 1.5),
                  ),
              ],
            ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: large ? 260 : 150, child: chart),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final s in series) LegendDot(color: s.colour, label: s.name),
            ...legend,
          ],
        ),
      ],
    );
  }
}

class BudgetVsActualChart extends StatelessWidget {
  const BudgetVsActualChart({
    super.key,
    required this.events,
    this.large = false,
  });

  final List<FinancialEventSummary> events;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final spent = BrutTone.brand.fill(context);
    final over = BrutTone.coral.fill(context);
    return _GroupedBars(
      large: large,
      empty: 'No event in this period has a budget yet.',
      labels: [for (final e in events) e.title],
      series: [
        _Series('Budget', context.palette.brandTint, [
          for (final e in events) e.allocatedBudget,
        ]),
        _Series('Spent', spent, [
          for (final e in events) e.spentToDate,
        ], colourAt: (i) => events[i].isOverBudget ? over : spent),
      ],
      legend: [LegendDot(color: over, label: 'Over budget')],
    );
  }
}

class InOutChart extends StatelessWidget {
  const InOutChart({super.key, required this.events, this.large = false});

  final List<FinancialEventSummary> events;
  final bool large;

  @override
  Widget build(BuildContext context) => _GroupedBars(
    large: large,
    empty: 'Nothing recorded against an event in this period.',
    labels: [for (final e in events) e.title],
    series: [
      _Series('In', BrutTone.mint.fill(context), [
        for (final e in events) e.totalIncome,
      ]),
      _Series('Out', BrutTone.orange.fill(context), [
        for (final e in events) e.totalExpenses,
      ]),
    ],
  );
}

/// A ring with the total in the middle and a ranked legend beside it.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.centre,
    required this.empty,
    this.large = false,
  });

  final List<(String, double, Color)> slices;
  final String centre;
  final String empty;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final s in slices)
        if (s.$2 > 0) s,
    ];
    final total = shown.fold(0.0, (sum, s) => sum + s.$2);
    if (total <= 0) return _NoData(message: empty);

    final size = large ? 200.0 : 120.0;
    final ink = context.palette.ink;
    final ring = SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 2,
              centerSpaceRadius: size * 0.3,
              pieTouchData: PieTouchData(enabled: false),
              sections: [
                for (final s in shown)
                  PieChartSectionData(
                    value: s.$2,
                    color: s.$3,
                    radius: size * 0.18,
                    showTitle: false,
                    borderSide: BorderSide(color: ink, width: 1.5),
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MonoLabel(centre, fontSize: large ? 10 : 8),
              Text(
                peso(total, decimals: 0),
                style: AppText.number.copyWith(fontSize: large ? 16 : 11),
              ),
            ],
          ),
        ],
      ),
    );

    // The tile has room for the biggest few; the page shows them all.
    final legend = [
      for (final s in large ? shown : shown.take(3))
        LegendRow(
          color: s.$3,
          label: s.$1,
          value: '${(s.$2 / total * 100).round()}%',
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: ring),
        SizedBox(height: large ? 16 : 10),
        for (final row in legend) ...[row, SizedBox(height: large ? 8 : 4)],
      ],
    );
  }
}

/// Income and spending as two lines across the period.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, this.large = false});

  final List<ReportTrendPoint> points;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final peak = points.fold(
      0.0,
      (most, p) => math.max(most, math.max(p.totalIncome, p.totalExpenses)),
    );
    if (points.isEmpty || peak <= 0) {
      return const _NoData(message: 'Nothing recorded in this period.');
    }

    final income = BrutTone.mint.fill(context);
    final spending = BrutTone.orange.fill(context);
    final ink = context.palette.ink;

    LineChartBarData line(double Function(ReportTrendPoint) value, Color c) =>
        LineChartBarData(
          spots: [
            for (final (i, p) in points.indexed) FlSpot(i.toDouble(), value(p)),
          ],
          color: c,
          barWidth: 3,
          isCurved: true,
          preventCurveOverShooting: true,
          dotData: FlDotData(show: points.length <= 12),
          belowBarData: BarAreaData(
            show: true,
            color: c.withValues(alpha: 0.15),
          ),
        );

    final chart = LineChart(
      LineChartData(
        minX: 0,
        // A single point still needs a width to sit in.
        maxX: math.max(1, points.length - 1).toDouble(),
        minY: 0,
        maxY: peak * 1.15,
        gridData: _grid(context),
        borderData: FlBorderData(show: false),
        titlesData: _titles(
          context,
          interval: math.max(1, (points.length / 6).ceil()).toDouble(),
          bottom: (i, meta) => i < 0 || i >= points.length
              ? const SizedBox.shrink()
              : Text(bucketLabel(points[i].bucket), style: _axis(context)),
        ),
        lineTouchData: LineTouchData(
          enabled: large,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => ink,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.barIndex == 0 ? 'In' : 'Out'} '
                  '${peso(s.y, decimals: 0)}',
                  AppText.caption.copyWith(
                    fontSize: 11,
                    color: context.palette.surface,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          line((p) => p.totalIncome, income),
          line((p) => p.totalExpenses, spending),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: large ? 240 : 140, child: chart),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: [
            LegendDot(color: income, label: 'Income'),
            LegendDot(color: spending, label: 'Spending'),
          ],
        ),
      ],
    );
  }
}

class LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const LegendDot({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: context.palette.ink, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

class LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String? value;
  const LegendRow({
    super.key,
    required this.color,
    required this.label,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: context.palette.ink, width: 1.5),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppText.body.copyWith(fontSize: 12.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (value != null)
          Text(value!, style: AppText.number.copyWith(fontSize: 12)),
      ],
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(message, style: AppText.caption),
  );
}
