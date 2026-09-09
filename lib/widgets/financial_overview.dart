import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Shared financial-overview widgets used across all three role
/// dashboards (Officer, Adviser, Admin) so their base financial view
/// stays visually and functionally identical, with each role's unique
/// content layered on top by the screen that uses these.

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.caption),
                const SizedBox(height: 4),
                Text(value, style: AppText.moneyLarge),
              ],
            ),
            Icon(icon, color: iconColor, size: 20),
          ],
        ),
      ),
    );
  }
}

class ExpendedCard extends StatelessWidget {
  final double expended;
  final double allocated;

  const ExpendedCard({super.key, required this.expended, required this.allocated});

  @override
  Widget build(BuildContext context) {
    final progress = allocated == 0 ? 0.0 : (expended / allocated).clamp(0.0, 1.0);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total expended', style: AppText.caption),
                    const SizedBox(height: 4),
                    Text('₱${expended.toStringAsFixed(2)}', style: AppText.moneyLarge),
                  ],
                ),
                const Icon(Icons.receipt_long_outlined, color: AppColors.inkMuted, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: AppColors.trackBg,
                color: progress >= 1.0 ? AppColors.brick : AppColors.indigo,
              ),
            ),
          ],
        ),
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
    final bg = isLow ? const Color(0xFFFBEAE7) : AppColors.sageTealTint;
    final border = isLow ? const Color(0xFFE3B3AA) : AppColors.sageTealBorder;
    final textColor = isLow ? AppColors.brick : AppColors.sageTealText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current remaining balance', style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 12, color: textColor)),
              const SizedBox(height: 4),
              Text(
                '₱${balance.toStringAsFixed(2)}',
                style: TextStyle(
                  fontFamily: AppText.monoFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 21,
                  color: textColor,
                ),
              ),
            ],
          ),
          Icon(isLow ? Icons.warning_amber_rounded : Icons.savings_outlined, color: textColor, size: 20),
        ],
      ),
    );
  }
}

class AllocationVsActualCard extends StatelessWidget {
  final Map<String, double> budgets;
  final Map<String, double> spend;

  const AllocationVsActualCard({super.key, required this.budgets, required this.spend});

  @override
  Widget build(BuildContext context) {
    final categories = budgets.keys.toList();
    final maxValue = [
      ...budgets.values,
      ...spend.values,
    ].fold(0.0, (a, b) => a > b ? a : b);
    final scale = maxValue == 0 ? 0.0 : 1 / maxValue;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Allocation vs actual', style: AppText.cardTitle),
            const SizedBox(height: 14),
            SizedBox(
              height: 90,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final c in categories)
                    _buildCluster(
                      allocatedFraction: (budgets[c] ?? 0) * scale,
                      actualFraction: (spend[c] ?? 0) * scale,
                      isOver: (spend[c] ?? 0) > (budgets[c] ?? 0),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final c in categories)
                  Expanded(
                    child: Text(
                      c.length > 8 ? c.substring(0, 8) : c,
                      textAlign: TextAlign.center,
                      style: AppText.caption,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: const [
                LegendDot(color: AppColors.indigoLightTint, label: 'Allocated'),
                SizedBox(width: 14),
                LegendDot(color: AppColors.indigo, label: 'Actual'),
                SizedBox(width: 14),
                LegendDot(color: AppColors.brick, label: 'Over'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCluster({
    required double allocatedFraction,
    required double actualFraction,
    required bool isOver,
  }) {
    const maxHeight = 80.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: allocatedFraction * maxHeight,
          decoration: const BoxDecoration(
            color: AppColors.indigoLightTint,
            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
        const SizedBox(width: 3),
        Container(
          width: 12,
          height: actualFraction * maxHeight,
          decoration: BoxDecoration(
            color: isOver ? AppColors.brick : AppColors.indigo,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
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
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

class ExpenseDistributionCard extends StatelessWidget {
  final Map<String, double> spendByCategory;
  const ExpenseDistributionCard({super.key, required this.spendByCategory});

  static const _categoryColors = {
    'Equipment': AppColors.indigo,
    'Venue': AppColors.marigold,
    'Catering': AppColors.sageTeal,
    'Marketing': AppColors.inkFaint,
  };

  @override
  Widget build(BuildContext context) {
    final total = spendByCategory.values.fold(0.0, (a, b) => a + b);
    final entries = spendByCategory.entries.where((e) => e.value > 0).toList();

    if (total == 0) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Expense distribution', style: AppText.cardTitle),
              SizedBox(height: 10),
              Text('No approved expenses yet.', style: AppText.caption),
            ],
          ),
        ),
      );
    }

    final colors = <Color>[];
    final stops = <double>[];
    double cursor = 0.0;
    for (final e in entries) {
      final share = e.value / total;
      final color = _categoryColors[e.key] ?? AppColors.inkFaint;
      colors.addAll([color, color]);
      stops.addAll([cursor, cursor + share]);
      cursor += share;
    }
    colors.add(colors.first);
    stops.add(1.0);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Expense distribution', style: AppText.cardTitle),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(colors: colors, stops: stops),
                  ),
                  child: Center(
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '₱${total.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontFamily: AppText.monoFamily,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in entries) ...[
                        LegendRow(
                          color: _categoryColors[e.key] ?? AppColors.inkFaint,
                          label: '${e.key} (${(e.value / total * 100).round()}%)',
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  const LegendRow({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppText.body.copyWith(fontSize: 12)),
      ],
    );
  }
}