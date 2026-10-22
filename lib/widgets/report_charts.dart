import 'package:flutter/material.dart';

import '../api/models/reports.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/peso.dart';
import '../api/models/income.dart';
import 'financial_overview.dart';

/// Where money came from, by source.
///
/// Registration, donations, sponsorship and the rest — the moderator's
/// twelfth point asks for the sources to be recorded, and this is them
/// read back.
class IncomeBySourceChart extends StatelessWidget {
  const IncomeBySourceChart({super.key, required this.sources});

  final List<IncomeSourceSummary> sources;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const _NoData(message: 'No income recorded in this period.');
    }

    final total = sources.fold(0.0, (sum, s) => sum + s.totalIncome);
    if (total <= 0) {
      return const _NoData(message: 'No income recorded in this period.');
    }

    final ordered = [...sources]
      ..sort((a, b) => b.totalIncome.compareTo(a.totalIncome));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < ordered.length; i++) ...[
          _Bar(
            label: ordered[i].sourceType.label,
            detail: peso(ordered[i].totalIncome, decimals: 0),
            fraction: ordered[i].totalIncome / total,
            colour: AppColors.accents[i % AppColors.accents.length],
          ),
          if (i != ordered.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// What each event took in against what it spent.
class EventBalanceChart extends StatelessWidget {
  const EventBalanceChart({super.key, required this.events});

  final List<FinancialEventSummary> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const _NoData(message: 'No events in this period.');
    }

    final peak = events.fold(
      0.0,
      (most, e) => [most, e.totalIncome, e.totalExpenses].reduce(
        (a, b) => a > b ? a : b,
      ),
    );
    if (peak <= 0) {
      return const _NoData(message: 'Nothing recorded against these events.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < events.length; i++) ...[
          Text(
            events[i].title,
            style: AppText.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          _Bar(
            label: 'In',
            detail: peso(events[i].totalIncome, decimals: 0),
            fraction: events[i].totalIncome / peak,
            colour: AppColors.mint,
          ),
          const SizedBox(height: 4),
          _Bar(
            label: 'Out',
            detail: peso(events[i].totalExpenses, decimals: 0),
            fraction: events[i].totalExpenses / peak,
            colour: AppColors.coral,
          ),
          if (i != events.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// One labelled bar. Shared so the two charts above read the same.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.detail,
    required this.fraction,
    required this.colour,
  });

  final String label;
  final String detail;
  final double fraction;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: AppText.caption.copyWith(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              color: context.palette.surface,
              border: Border.all(color: context.palette.ink, width: 1.5),
              borderRadius: AppRadius.controlAll,
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              // A line with nothing in it reads as a bug; a sliver reads
              // as a small number, which is what it is.
              widthFactor: fraction.clamp(0.0, 1.0) == 0
                  ? 0.0
                  : fraction.clamp(0.02, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: AppRadius.controlAll,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(detail, style: AppText.caption.copyWith(fontSize: 11)),
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

/// The four charts this screen offers, each with a name and a builder.
///
/// Kept in one place so the grid and the full-screen view cannot drift
/// apart: the tile and the page it opens are the same chart.
class ReportChart {
  const ReportChart({
    required this.title,
    required this.explanation,
    required this.build,
    this.selfTitled = false,
  });

  final String title;
  final String explanation;
  final Widget Function(BuildContext context) build;

  /// Whether the chart draws its own heading. Two of these are existing
  /// cards that do, and a tile putting its own title above them showed
  /// the same words twice.
  final bool selfTitled;

  static List<ReportChart> all({
    required Map<String, double> budgets,
    required Map<String, double> spend,
    required List<IncomeSourceSummary> sources,
    required List<FinancialEventSummary> events,
  }) => [
    ReportChart(
      title: 'Allocation vs actual',
      explanation: 'What each category was given against what it has used.',
      selfTitled: true,
      build: (_) => AllocationVsActualCard(budgets: budgets, spend: spend),
    ),
    ReportChart(
      title: 'Where it went',
      explanation: 'Approved spending split by category.',
      selfTitled: true,
      build: (_) => ExpenseDistributionCard(spendByCategory: spend),
    ),
    ReportChart(
      title: 'Where it came from',
      explanation: 'Income by source: fees, donations, sponsorship.',
      build: (_) => IncomeBySourceChart(sources: sources),
    ),
    ReportChart(
      title: 'In and out by event',
      explanation: 'What each event took in against what it spent.',
      build: (_) => EventBalanceChart(events: events),
    ),
  ];
}
