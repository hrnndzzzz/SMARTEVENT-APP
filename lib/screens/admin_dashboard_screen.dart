import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/expense_review.dart';
import '../widgets/financial_overview.dart';
import 'notifications_screen.dart';
import 'event_detail_screen.dart';
import 'reports_screen.dart';
import 'events_screen.dart' show eventStatusTone;
import 'expense_detail_screen.dart' show expenseStatusTone;

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Future<void> _setCategoryBudget(BuildContext context) async {
    final app = context.read<AppState>();
    final categories = app.expenseCategories;

    // The category list is empty before the first successful load, and
    // stays empty when that load failed. Both cases used to reach
    // `categories.first` and throw "Bad state: No element".
    if (categories.isEmpty) {
      final failure = app.categoriesLoad.error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failure ??
                'No categories exist yet. Create one before setting a budget.',
          ),
        ),
      );
      return;
    }

    String selected = categories.first;
    final controller = TextEditingController(
      text: (app.categoryBudgets[selected] ?? 0).toStringAsFixed(2),
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Set category budget', style: AppText.cardTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrutDropdown<String>(
                label: 'Category',
                value: selected,
                hint: 'Select a category',
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) {
                  setDialogState(() {
                    selected = v!;
                    controller.text = (app.categoryBudgets[selected] ?? 0)
                        .toStringAsFixed(2);
                  });
                },
              ),
              const SizedBox(height: 14),
              BrutTextField(
                label: 'Amount',
                controller: controller,
                prefixIcon: Icons.payments_outlined,
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            BrutButton(
              label: 'Save',
              expand: false,
              size: BrutSize.small,
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final amount = double.tryParse(controller.text.trim());
                Navigator.pop(context);
                if (amount == null || amount < 0) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid amount.'),
                    ),
                  );
                  return;
                }
                // Awaited, and the result is reported. This used to fire
                // and forget, then announce success — so a 403, a 409 or
                // a dead backend still told the admin the budget was set.
                final error = await app.setCategoryBudget(selected, amount);
                if (!messenger.mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      error ??
                          '$selected budget set to '
                              '₱${amount.toStringAsFixed(2)}',
                    ),
                    duration: Duration(seconds: error == null ? 3 : 6),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BrutScreen(
      topBar: AppHeader(
        onBack: () => Navigator.of(context).maybePop(),
        onBellTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      ),
      scrollable: false,
      bottomPadding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Consumer<AppState>(
              builder: (context, app, _) {
                final pendingEvents = app.pendingAdminEvents;
                final handledEvents = app.adminHandledEvents;
                final pendingExpenses = app.pendingExpenses;
                final handledExpenses = app.expenses
                    .where((e) => e.status != ExpenseStatus.pending)
                    .toList();

                return ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    MetricCard(
                      label: 'Total budget allocated',
                      value: '₱${app.totalAllocated.toStringAsFixed(2)}',
                      icon: Icons.account_balance_wallet_outlined,
                      tone: BrutTone.brand,
                    ),
                    const SizedBox(height: 10),
                    ExpendedCard(
                      expended: app.totalExpended,
                      allocated: app.totalAllocated,
                    ),
                    const SizedBox(height: 10),
                    RemainingBalanceCard(balance: app.remainingBalance),
                    const SizedBox(height: 16),
                    AllocationVsActualCard(
                      budgets: app.categoryBudgets,
                      spend: app.spendByCategory,
                    ),
                    const SizedBox(height: 10),
                    ExpenseDistributionCard(
                      spendByCategory: app.spendByCategory,
                    ),
                    const SizedBox(height: 16),
                    _QuickActionsRow(
                      onSetBudget: () => _setCategoryBudget(context),
                      onOpenReports: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReportsScreen(),
                        ),
                      ),
                      onViewAnalytics: () => BrutSheet.show<void>(
                        context,
                        builder: (_) => const _AnalyticsSheet(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    BrutSectionTitle(
                      'Pending final approval',
                      aside: MonoLabel('${pendingEvents.length} waiting'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap a request to review and decide.',
                      style: AppText.caption,
                    ),
                    const SizedBox(height: 10),
                    if (pendingEvents.isEmpty)
                      const BrutEmptyState(
                        title: 'All caught up',
                        hint: 'Nothing is waiting on final approval.',
                        icon: Icons.task_alt,
                      )
                    else
                      for (final event in pendingEvents) ...[
                        _EventSummaryCard(
                          event: event,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EventDetailScreen(event: event),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    if (pendingExpenses.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      BrutSectionTitle(
                        'Pending expenses',
                        aside: MonoLabel('${pendingExpenses.length} waiting'),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap to approve or reject.',
                        style: AppText.caption,
                      ),
                      const SizedBox(height: 10),
                      for (final expense in pendingExpenses) ...[
                        ExpensePendingCard(
                          expense: expense,
                          reviewerRole: 'Admin',
                          onInsufficientBudget: () =>
                              _setCategoryBudget(context),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                    if (handledEvents.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const BrutSectionTitle('Recently handled events'),
                      const SizedBox(height: 10),
                      for (final event in handledEvents) ...[
                        _HandledEventRow(
                          event: event,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EventDetailScreen(event: event),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                    if (handledExpenses.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const BrutSectionTitle('Recently handled expenses'),
                      const SizedBox(height: 10),
                      for (final expense in handledExpenses) ...[
                        _HandledExpenseRow(expense: expense),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  final VoidCallback onSetBudget;
  final VoidCallback onOpenReports;
  final VoidCallback onViewAnalytics;

  const _QuickActionsRow({
    required this.onSetBudget,
    required this.onOpenReports,
    required this.onViewAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Set Budget',
            accent: BrutTone.brand,
            onTap: onSetBudget,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.description_outlined,
            label: 'Reports',
            accent: BrutTone.mint,
            onTap: onOpenReports,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.bar_chart_outlined,
            label: 'Analytics',
            accent: BrutTone.coral,
            onTap: onViewAnalytics,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final BrutTone accent;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BrutSurface(
      onTap: onTap,
      enabled: onTap != null,
      fill: accent.fill(context),
      radius: AppRadius.rowAll,
      shadow: AppShadows.base,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.palette.ink, size: 20),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.buttonLabel.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _EventSummaryCard extends StatelessWidget {
  final EventItem event;
  final VoidCallback onTap;

  const _EventSummaryCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The adviser already looked at this; say what they said rather
          // than making the admin go and find it.
          if (event.adviserApprovalNote?.isNotEmpty == true) ...[
            BrutInlineMessage(
              tone: BrutTone.mint,
              icon: Icons.check_circle_outline,
              text: 'Adviser-approved · "${event.adviserApprovalNote}"',
            ),
            const SizedBox(height: 12),
          ],
          Text(event.title, style: AppText.cardTitle),
          const SizedBox(height: 3),
          Text('${event.org} · ${event.date}', style: AppText.caption),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                event.budget,
                style: AppText.moneyLarge.copyWith(fontSize: 17),
              ),
              const Spacer(),
              Text(
                'Review',
                style: AppText.buttonLabel.copyWith(fontSize: 12.5),
              ),
              Icon(Icons.chevron_right, size: 18, color: context.palette.ink),
            ],
          ),
        ],
      ),
    );
  }
}

class _HandledEventRow extends StatelessWidget {
  final EventItem event;
  final VoidCallback onTap;
  const _HandledEventRow({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BrutListRow(
      title: event.title,
      meta: event.statusLabel,
      onTap: onTap,
      marker: BrutIconTile(
        icon: event.status == EventApprovalStatus.rejected
            ? Icons.cancel_outlined
            : Icons.check_circle_outline,
        tone: eventStatusTone(event.status),
        size: 30,
      ),
    );
  }
}

class _HandledExpenseRow extends StatelessWidget {
  final ExpenseEntry expense;
  const _HandledExpenseRow({required this.expense});

  @override
  Widget build(BuildContext context) {
    final isRejected = expense.status == ExpenseStatus.rejected;
    return BrutListRow(
      title: expense.vendor,
      meta:
          '₱${expense.amount.toStringAsFixed(2)} · '
          '${isRejected ? 'Rejected' : 'Approved'}',
      marker: BrutIconTile(
        icon: isRejected ? Icons.cancel_outlined : Icons.check_circle_outline,
        tone: expenseStatusTone(expense.status),
        size: 30,
      ),
    );
  }
}

/// The server's own dashboard figures.
///
/// This used to recount the loaded lists on the phone, which meant it
/// could disagree with the printed reports — and the reports are right.
/// It calls `/analytics/dashboard` instead and shows what comes back,
/// including the counts the cards behind it do not carry.
class _AnalyticsSheet extends StatefulWidget {
  const _AnalyticsSheet();

  @override
  State<_AnalyticsSheet> createState() => _AnalyticsSheetState();
}

class _AnalyticsSheetState extends State<_AnalyticsSheet> {
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
          child: Center(child: CircularProgressIndicator()),
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
              BrutDetailRow(
                'Allocated',
                '₱${allocated.toStringAsFixed(2)}',
                mono: true,
              ),
              const SizedBox(height: 8),
              BrutDetailRow(
                'Spent (approved)',
                '₱${spent.toStringAsFixed(2)}',
                mono: true,
              ),
              const SizedBox(height: 8),
              BrutDetailRow(
                'Remaining',
                '₱${data.totalRemainingBudget.toStringAsFixed(2)}',
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
