import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/expense_review.dart';
import '../widgets/financial_overview.dart';
import 'notifications_screen.dart';
import 'event_detail_screen.dart';
import 'events_screen.dart' show eventStatusTone;
import 'expense_detail_screen.dart' show expenseStatusTone;

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _generatingReport = false;

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
              onPressed: () {
                final amount = double.tryParse(controller.text.trim());
                Navigator.pop(context);
                if (amount == null || amount < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid amount.'),
                    ),
                  );
                  return;
                }
                app.setCategoryBudget(selected, amount);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '$selected budget set to ₱${amount.toStringAsFixed(2)}',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateReports() async {
    setState(() => _generatingReport = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _generatingReport = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Org-wide financial summary generated — org_summary_q2_2026.pdf',
        ),
      ),
    );
  }

  Future<void> _viewAnalytics(BuildContext context) async {
    final app = context.read<AppState>();
    final allocated = app.totalAllocated;
    final expended = app.totalExpended;
    final utilization = allocated == 0 ? 0.0 : (expended / allocated * 100);
    final spend = app.spendByCategory;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Org-Wide Analytics', style: AppText.cardTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _analyticsRow(
                'Total budget allocated',
                '₱${allocated.toStringAsFixed(2)}',
              ),
              _analyticsRow(
                'Total expended (approved)',
                '₱${expended.toStringAsFixed(2)}',
              ),
              _analyticsRow(
                'Overall utilization',
                '${utilization.toStringAsFixed(0)}%',
              ),
              const SizedBox(height: 12),
              const Text('By category', style: AppText.caption),
              const SizedBox(height: 8),
              if (expended == 0)
                const Text('No approved expenses yet.', style: AppText.caption)
              else
                for (final entry in spend.entries.where((e) => e.value > 0))
                  _analyticsRow(
                    entry.key,
                    '${(entry.value / expended * 100).toStringAsFixed(0)}%',
                    indent: true,
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _analyticsRow(String label, String value, {bool indent = false}) {
    return Padding(
      padding: EdgeInsets.only(left: indent ? 12 : 0, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body.copyWith(fontSize: 13)),
          Text(value, style: AppText.number),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BrutScreen(
      topBar: AppHeader(
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
                      onGenerateReports: _generatingReport
                          ? null
                          : _generateReports,
                      onViewAnalytics: () => _viewAnalytics(context),
                      isGenerating: _generatingReport,
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
  final VoidCallback? onGenerateReports;
  final VoidCallback onViewAnalytics;
  final bool isGenerating;

  const _QuickActionsRow({
    required this.onSetBudget,
    required this.onGenerateReports,
    required this.onViewAnalytics,
    required this.isGenerating,
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
            label: isGenerating ? 'Generating...' : 'Reports',
            accent: BrutTone.mint,
            onTap: onGenerateReports,
            loading: isGenerating,
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
  final bool loading;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.accent,
    this.onTap,
    this.loading = false,
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
          loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.palette.ink,
                  ),
                )
              : Icon(icon, color: context.palette.ink, size: 20),
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
