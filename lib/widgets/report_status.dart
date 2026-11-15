import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Which organization the analytics cover: all the account can see, or
/// one, such as JPSSITE. The report, its exports and "Needs a look" all
/// follow it, so they always cover the same organizations.
///
/// Only Admins and the Super Admin choose. An Adviser or officer sees only
/// their own organization anyway, so they are shown its name instead.
class ReportOrganizationPicker extends StatelessWidget {
  const ReportOrganizationPicker({super.key, this.onChanged});

  /// Called after the choice changes, to reload whatever shows it.
  final VoidCallback? onChanged;

  // "All organizations" is a choice, so it needs a value null is not.
  static const _all = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.choosesReportOrganization) {
      final own = app.currentAccount?.organizationName;
      if (own == null || own.isEmpty) return const SizedBox.shrink();
      return Row(
        children: [
          const MonoLabel('Organization'),
          const SizedBox(width: AppLayout.tight),
          Flexible(child: BrutBadge(label: own, tone: BrutTone.brand)),
        ],
      );
    }
    return BrutDropdown<String>(
      label: 'Organization',
      value: app.reportOrganizationId ?? _all,
      hint: 'All organizations',
      items: [
        const DropdownMenuItem(value: _all, child: Text('All organizations')),
        for (final o in app.organizations)
          DropdownMenuItem(value: o.id, child: Text(o.label)),
      ],
      onChanged: (id) {
        if (id == null || id == (app.reportOrganizationId ?? _all)) return;
        id == _all
            ? app.setReportFilters(clearOrganization: true)
            : app.setReportFilters(organizationId: id);
        onChanged?.call();
      },
    );
  }
}

String eventStatusLabel(String key) => switch (key) {
  'pending_adviser' => 'Pending adviser',
  'pending_admin' => 'Pending admin',
  'pending_institutional_review' => 'Pending SDS',
  'pending' => 'Pending',
  'draft' => 'Draft',
  'approved' => 'Approved',
  'rejected' => 'Rejected',
  'completed' => 'Completed',
  final other => other,
};

BrutTone eventStatusTone(String key) => switch (key) {
  'approved' || 'completed' => BrutTone.mint,
  'rejected' => BrutTone.coral,
  'draft' => BrutTone.neutral,
  _ => BrutTone.sun,
};

/// How many events sit at each stage, as badges.
class StatusCounts extends StatelessWidget {
  const StatusCounts({super.key, required this.title, required this.counts});

  final String title;
  final Map<String, int> counts;

  // Both pending stages stay separate: an event waiting on the adviser is
  // in a different queue from one waiting on an admin.
  static const _order = [
    'draft',
    'pending_adviser',
    'pending_admin',
    'pending_institutional_review',
    'pending',
    'approved',
    'rejected',
    'completed',
  ];

  @override
  Widget build(BuildContext context) {
    // A status nobody reported is absent, not zero; a zero would invent a
    // row.
    final shown = [
      for (final key in _order)
        if (counts.containsKey(key)) key,
      for (final key in counts.keys)
        if (!_order.contains(key)) key,
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
                    label: '${eventStatusLabel(key)} · ${counts[key]}',
                    tone: eventStatusTone(key),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Flagged expenses, low stock and unconfirmed items: what is waiting on
/// someone right now, whatever period is chosen.
class NeedsALook extends StatelessWidget {
  const NeedsALook({super.key, required this.data});

  final DashboardSummary data;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrutSectionTitle('Needs a look'),
          const SizedBox(height: 4),
          const Text(
            'Right now, whatever period is chosen.',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          _Need(
            label: 'Flagged expenses',
            count: data.flaggedExpenseCount,
            hint:
                'A receipt resembled another, or an OCR amount disagreed. '
                'A prompt to look, not a finding.',
          ),
          const SizedBox(height: 10),
          _Need(
            label: 'Low stock',
            count: data.lowStockItemCount,
            hint: 'At or below the threshold set on the item.',
          ),
          const SizedBox(height: 10),
          _Need(
            label: 'Unconfirmed draft items',
            count: data.draftInventoryCount,
            hint:
                'Created by a completed purchase, waiting for an '
                'administrator to confirm them.',
          ),
        ],
      ),
    );
  }
}

class _Need extends StatelessWidget {
  const _Need({required this.label, required this.count, required this.hint});

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
