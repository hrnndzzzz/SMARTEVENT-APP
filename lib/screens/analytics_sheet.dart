import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models/reports.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/peso.dart';

/// The server's own dashboard figures.
///
/// This used to recount the loaded lists on the phone, which meant it
/// could disagree with the printed reports — and the reports are right.
/// It calls `/analytics/dashboard` instead and shows what comes back,
/// including the counts the cards behind it do not carry.
class AnalyticsSheet extends StatefulWidget {
  const AnalyticsSheet({super.key});

  @override
  State<AnalyticsSheet> createState() => AnalyticsSheetState();
}

class AnalyticsSheetState extends State<AnalyticsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.dashboardLoad;
    final data = app.dashboard;

    return BrutSheet(
      title: 'Organization analytics',
      subtitle: 'Straight from the server, so these agree with the reports.',
      child: switch (load) {
        _ when load.isLoading && data == null => const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: BrutSpinner()),
        ),
        _ when load.hasFailed && data == null => BrutInlineMessage(
          text: load.error!,
          tone: BrutTone.coral,
        ),
        _ when data == null => const BrutEmptyState(
          title: 'Nothing to show yet',
          hint: 'The server returned no figures.',
          icon: Icons.bar_chart_outlined,
        ),
        _ => _Figures(data: data),
      },
    );
  }
}

class _Figures extends StatelessWidget {
  const _Figures({required this.data});

  final DashboardSummary data;

  @override
  Widget build(BuildContext context) {
    final allocated = data.totalAllocatedBudget;
    final spent = data.totalSpent;
    final used = allocated == 0 ? 0.0 : spent / allocated;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrutSectionTitle('Budget'),
              const SizedBox(height: 12),
              BrutDetailRow('Allocated', '${peso(allocated)}', mono: true),
              const SizedBox(height: 8),
              BrutDetailRow('Spent (approved)', '${peso(spent)}', mono: true),
              const SizedBox(height: 8),
              BrutDetailRow(
                'Remaining',
                '${peso(data.totalRemainingBudget)}',
                mono: true,
              ),
              const SizedBox(height: 12),
              BrutProgressBar(
                value: used,
                tone: used > 1 ? BrutTone.coral : BrutTone.brand,
              ),
              const SizedBox(height: 6),
              MonoLabel(
                '${(used * 100).isFinite ? (used * 100).round() : 0}% used '
                'across ${data.totalCategories} '
                '${data.totalCategories == 1 ? 'category' : 'categories'}',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppLayout.between),
        _Counts(
          title: 'Events',
          counts: data.eventsByStatus,
          // Both pending stages stay separate: an event waiting on the
          // adviser is in a different queue from one waiting on an admin.
          order: const [
            'draft',
            'pending_adviser',
            'pending_admin',
            'pending',
            'approved',
            'rejected',
            'completed',
          ],
        ),
        const SizedBox(height: AppLayout.between),
        _Counts(
          title: 'Expenses',
          counts: data.expensesByStatus,
          order: const ['pending', 'approved', 'rejected'],
        ),
        const SizedBox(height: AppLayout.between),
        BrutCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrutSectionTitle('Needs a look'),
              const SizedBox(height: 12),
              _Needs(
                label: 'Flagged expenses',
                count: data.flaggedExpenseCount,
                hint:
                    'A receipt resembled another, or an OCR amount '
                    'disagreed. A prompt to look, not a finding.',
              ),
              const SizedBox(height: 10),
              _Needs(
                label: 'Low stock',
                count: data.lowStockItemCount,
                hint: 'At or below the threshold set on the item.',
              ),
              const SizedBox(height: 10),
              _Needs(
                label: 'Unconfirmed draft items',
                count: data.draftInventoryCount,
                hint:
                    'Created by a completed purchase, waiting for an '
                    'administrator to confirm them.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({
    required this.title,
    required this.counts,
    required this.order,
  });

  final String title;
  final Map<String, int> counts;
  final List<String> order;

  static String _label(String key) => switch (key) {
    'pending_adviser' => 'Pending adviser',
    'pending_admin' => 'Pending admin',
    'pending' => 'Pending',
    'draft' => 'Draft',
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'completed' => 'Completed',
    final other => other,
  };

  static BrutTone _tone(String key) => switch (key) {
    'approved' || 'completed' => BrutTone.mint,
    'rejected' => BrutTone.coral,
    'draft' => BrutTone.neutral,
    _ => BrutTone.sun,
  };

  @override
  Widget build(BuildContext context) {
    // A status the server did not mention is not zero — it is absent, and
    // showing it as zero would invent a row.
    final shown = [
      for (final key in order)
        if (counts.containsKey(key)) key,
      for (final key in counts.keys)
        if (!order.contains(key)) key,
    ];

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrutSectionTitle(title),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            const Text('None recorded yet.', style: AppText.caption)
          else
            Wrap(
              spacing: AppLayout.tight,
              runSpacing: AppLayout.tight,
              children: [
                for (final key in shown)
                  BrutBadge(
                    label: '${_label(key)} · ${counts[key]}',
                    tone: _tone(key),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Needs extends StatelessWidget {
  const _Needs({required this.label, required this.count, required this.hint});

  final String label;
  final int count;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppText.body.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(hint, style: AppText.caption),
            ],
          ),
        ),
        const SizedBox(width: AppLayout.between),
        BrutBadge(
          label: '$count',
          tone: count == 0 ? BrutTone.mint : BrutTone.sun,
          mono: true,
        ),
      ],
    );
  }
}
