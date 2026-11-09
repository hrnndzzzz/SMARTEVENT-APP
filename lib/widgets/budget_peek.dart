import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import '../theme/peso.dart';

/// Where the money has gone, by category, for a hold.
///
/// Built to read like [EventProgressPeek]: one titled row per thing,
/// with a bar under it saying how far along it is. There the bar is a
/// workflow; here it is a budget. Same shape, so a hold means the same
/// thing wherever it is used.
class BudgetPeek extends StatelessWidget {
  const BudgetPeek({super.key, required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const Text(
        'No budget categories yet, so there is nothing to spend against.',
        style: AppText.body,
      );
    }

    // Tightest first: the one about to run out is the reason anyone
    // held this tile, and it should not be at the bottom of the list.
    final rows = [...categories]
      ..sort((a, b) => _used(b).compareTo(_used(a)));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _CategoryRow(category: rows[i]),
          if (i != rows.length - 1) const SizedBox(height: AppLayout.tight),
        ],
      ],
    );
  }

  static double _used(Category c) => c.allocatedBudget <= 0
      ? 0
      : ((c.allocatedBudget - c.remainingBudget) / c.allocatedBudget)
            .clamp(0.0, 1.0);
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final used = BudgetPeek._used(category);
    // Over, nearly out, or fine. The same three readings the tile on
    // the dashboard gives, so the detail agrees with the summary.
    final tone = switch (used) {
      >= 1 => BrutTone.coral,
      >= 0.9 => BrutTone.sun,
      _ => BrutTone.orange,
    };

    return BrutCard(
      radius: AppRadius.rowAll,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle.copyWith(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                peso(category.remainingBudget, decimals: 0),
                style: AppText.number.copyWith(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BrutProgressBar(value: used, tone: tone),
          const SizedBox(height: 6),
          Text(
            '${(used * 100).round()}% of '
            '${peso(category.allocatedBudget, decimals: 0)} used',
            style: AppText.caption.copyWith(color: p.muted),
          ),
        ],
      ),
    );
  }
}
