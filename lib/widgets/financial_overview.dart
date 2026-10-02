import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Shared financial-overview widgets used across all three role
/// dashboards (Officer, Adviser, Admin) so their base financial view
/// stays visually and functionally identical, with each role's unique
/// content layered on top by the screen that uses these.
///
/// Every amount here is mono with tabular figures, so columns of money
/// line up instead of jittering row to row.

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  /// The meaning of the number, which decides the icon tile's fill. Use
  /// [BrutTone.neutral] for a figure that is neither good nor bad.
  final BrutTone tone;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = BrutTone.brand,
  });

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Row(
        children: [
          BrutIconTile(icon: icon, tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MonoLabel(label),
                const SizedBox(height: 4),
                Text(value, style: AppText.moneyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExpendedCard extends StatelessWidget {
  final double expended;
  final double allocated;

  const ExpendedCard({
    super.key,
    required this.expended,
    required this.allocated,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = allocated == 0 ? 0.0 : expended / allocated;
    final isOver = ratio > 1;
    final percent = (ratio * 100).isFinite ? (ratio * 100).round() : 0;

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BrutIconTile(
                icon: Icons.receipt_long_outlined,
                tone: isOver ? BrutTone.coral : BrutTone.neutral,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MonoLabel('Total expended'),
                    const SizedBox(height: 4),
                    Text('₱${expended.toStringAsFixed(2)}',
                        style: AppText.moneyLarge),
                  ],
                ),
              ),
              // The state is said in words as well as in colour, because
              // colour alone is not a signal everyone receives.
              BrutBadge(
                label: isOver ? 'Over' : '$percent%',
                tone: isOver ? BrutTone.coral : BrutTone.neutral,
                mono: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          BrutProgressBar(
            value: ratio,
            tone: isOver ? BrutTone.coral : BrutTone.brand,
          ),
        ],
      ),
    );
  }
}

class RemainingBalanceCard extends StatelessWidget {
  final double balance;
  const RemainingBalanceCard({super.key, required this.balance});

  @override
  Widget build(BuildContext context) {
    final isLow = balance < 500;
    final tone = isLow ? BrutTone.coral : BrutTone.mint;

    return BrutCard(
      tone: tone,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MonoLabel('Remaining balance', color: tone.foreground),
                const SizedBox(height: 4),
                Text(
                  '₱${balance.toStringAsFixed(2)}',
                  style: AppText.moneyLarge.copyWith(color: tone.foreground),
                ),
                if (isLow) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Running low — under ₱500 left.',
                    style: AppText.caption.copyWith(color: tone.foreground),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            isLow ? Icons.warning_amber_rounded : Icons.savings_outlined,
            color: tone.foreground,
            size: 22,
          ),
        ],
      ),
    );
  }
}

class AllocationVsActualCard extends StatelessWidget {
  final Map<String, double> budgets;
  final Map<String, double> spend;

  const AllocationVsActualCard({
    super.key,
    required this.budgets,
    required this.spend,
  });

  @override
  Widget build(BuildContext context) {
    final categories = budgets.keys.toList();
    final maxValue = [
      ...budgets.values,
      ...spend.values,
    ].fold(0.0, (a, b) => a > b ? a : b);
    final scale = maxValue == 0 ? 0.0 : 1 / maxValue;

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrutSectionTitle('Allocation vs actual'),
          const SizedBox(height: 16),
          if (categories.isEmpty)
            const BrutEmptyState(
              title: 'No categories yet',
              hint: 'Budget categories appear here once they are set up.',
            )
          else ...[
            SizedBox(
              height: 92,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final c in categories)
                    Expanded(
                      child: _Cluster(
                        allocatedFraction: (budgets[c] ?? 0) * scale,
                        actualFraction: (spend[c] ?? 0) * scale,
                        isOver: (spend[c] ?? 0) > (budgets[c] ?? 0),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final c in categories)
                  Expanded(
                    child: Center(
                      // Two lines rather than a truncation: a chart axis
                      // that says CATERIN explains nothing.
                      child: Text(
                        c.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.monoLabel
                            .copyWith(fontSize: 8, letterSpacing: 0.4),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                LegendDot(color: AppColors.brandTint, label: 'Allocated'),
                LegendDot(color: AppColors.brand, label: 'Actual'),
                LegendDot(color: AppColors.coral, label: 'Over'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Cluster extends StatelessWidget {
  const _Cluster({
    required this.allocatedFraction,
    required this.actualFraction,
    required this.isOver,
  });

  final double allocatedFraction;
  final double actualFraction;
  final bool isOver;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Bar(fraction: allocatedFraction, fill: AppColors.brandTint),
        const SizedBox(width: 4),
        _Bar(
          fraction: actualFraction,
          fill: isOver ? AppColors.coral : AppColors.brand,
        ),
      ],
    );
  }
}

/// A flat colour block with the same 2px outline as everything else, so
/// the chart belongs to the rest of the screen rather than looking like a
/// charting library dropped into it.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.fill});

  final double fraction;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    const maxHeight = 84.0;
    final safe = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
    // A bar never collapses below its own outline, or it reads as missing
    // data rather than as a small number.
    final height = (safe * maxHeight).clamp(6.0, maxHeight);

    return Container(
      width: 14,
      height: height,
      decoration: BoxDecoration(
        color: fill,
        border: AppBorders.all,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.control),
        ),
      ),
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
            border: Border.all(color: AppColors.ink, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

class ExpenseDistributionCard extends StatelessWidget {
  final Map<String, double> spendByCategory;
  const ExpenseDistributionCard({super.key, required this.spendByCategory});

  /// One colour per category, taken from the shared accents so a category
  /// never borrows a colour that already means something else.
  static Color colorFor(String category, int index) => switch (category) {
        'Equipment' => AppColors.brand,
        'Venue' => AppColors.sun,
        'Catering' => AppColors.mint,
        'Marketing' => AppColors.violet,
        _ => AppColors.accents[index % AppColors.accents.length],
      };

  @override
  Widget build(BuildContext context) {
    final total = spendByCategory.values.fold(0.0, (a, b) => a + b);
    final entries = spendByCategory.entries.where((e) => e.value > 0).toList();

    if (total == 0 || entries.isEmpty) {
      return const BrutCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrutSectionTitle('Expense distribution'),
            SizedBox(height: 12),
            BrutEmptyState(
              title: 'No approved expenses yet',
              hint: 'The split appears once an adviser approves one.',
            ),
          ],
        ),
      );
    }

    final colors = <Color>[];
    final stops = <double>[];
    double cursor = 0.0;
    for (var i = 0; i < entries.length; i++) {
      final share = entries[i].value / total;
      final color = colorFor(entries[i].key, i);
      colors.addAll([color, color]);
      stops.addAll([cursor, cursor + share]);
      cursor += share;
    }
    colors.add(colors.first);
    stops.add(1.0);

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrutSectionTitle('Expense distribution'),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: AppBorders.all,
                  gradient: SweepGradient(colors: colors, stops: stops),
                ),
                child: Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: AppBorders.all,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '₱${total.toStringAsFixed(0)}',
                      style: AppText.number.copyWith(fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < entries.length; i++) ...[
                      LegendRow(
                        color: colorFor(entries[i].key, i),
                        label: entries[i].key,
                        value:
                            '${(entries[i].value / total * 100).round()}%',
                      ),
                      if (i != entries.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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
            border: Border.all(color: AppColors.ink, width: 1.5),
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
