import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/expense_review.dart';
import '../widgets/financial_overview.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';
import 'event_detail_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _generatingReport = false;

  Future<void> _setCategoryBudget(BuildContext context) async {
    final app = context.read<AppState>();
    final categories = AppState.expenseCategories;
    String selected = categories.first;
    final controller = TextEditingController(text: app.categoryBudgets[selected]!.toStringAsFixed(2));

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Set Category Budget', style: AppText.cardTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Category', style: AppText.caption),
              const SizedBox(height: 6),
              DropdownButton<String>(
                value: selected,
                isExpanded: true,
                items: [
                  for (final c in categories) DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) {
                  setDialogState(() {
                    selected = v!;
                    controller.text = app.categoryBudgets[selected]!.toStringAsFixed(2);
                  });
                },
              ),
              const SizedBox(height: 14),
              const Text('Amount (₱)', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: '0.00'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(controller.text.trim());
                Navigator.pop(context);
                if (amount == null || amount < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid amount.')),
                  );
                  return;
                }
                app.setCategoryBudget(selected, amount);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$selected budget set to ₱${amount.toStringAsFixed(2)}')),
                );
              },
              child: const Text('Save'),
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
      const SnackBar(content: Text('Org-wide financial summary generated — org_summary_q2_2026.pdf')),
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
              _analyticsRow('Total budget allocated', '₱${allocated.toStringAsFixed(2)}'),
              _analyticsRow('Total expended (approved)', '₱${expended.toStringAsFixed(2)}'),
              _analyticsRow('Overall utilization', '${utilization.toStringAsFixed(0)}%'),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
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
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppText.monoFamily,
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                subtitle: 'System Administrator',
                subtitleBg: const Color(0xFFE8ECF3),
                subtitleColor: AppColors.indigo,
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Consumer<AppState>(
                  builder: (context, app, _) {
                    final pendingEvents = app.pendingAdminEvents;
                    final handledEvents = app.adminHandledEvents;
                    final pendingExpenses = app.pendingExpenses;
                    final handledExpenses = app.expenses.where((e) => e.status != ExpenseStatus.pending).toList();

                    return ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        MetricCard(
                          label: 'Total budget allocated',
                          value: '₱${app.totalAllocated.toStringAsFixed(2)}',
                          icon: Icons.account_balance_wallet_outlined,
                          iconColor: AppColors.indigo,
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
                        ExpenseDistributionCard(spendByCategory: app.spendByCategory),
                        const SizedBox(height: 16),
                        _QuickActionsRow(
                          onSetBudget: () => _setCategoryBudget(context),
                          onGenerateReports: _generatingReport ? null : _generateReports,
                          onViewAnalytics: () => _viewAnalytics(context),
                          isGenerating: _generatingReport,
                        ),
                        const SizedBox(height: 18),
                        Text('Pending final approval (${pendingEvents.length})', style: AppText.cardTitle),
                        const SizedBox(height: 4),
                        const Text('Tap a request to review and decide.', style: AppText.caption),
                        const SizedBox(height: 10),
                        if (pendingEvents.isEmpty)
                          const _EmptyState(text: 'No pending approvals. All caught up.')
                        else
                          for (final event in pendingEvents) ...[
                            _EventSummaryCard(
                              event: event,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        if (pendingExpenses.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text('Pending expenses (${pendingExpenses.length})', style: AppText.cardTitle),
                          const SizedBox(height: 4),
                          const Text('Tap to approve or reject.', style: AppText.caption),
                          const SizedBox(height: 10),
                          for (final expense in pendingExpenses) ...[
                            ExpensePendingCard(
                              expense: expense,
                              reviewerRole: 'Admin',
                              onInsufficientBudget: () => _setCategoryBudget(context),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                        if (handledEvents.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          const Text('Recently handled events', style: AppText.caption),
                          const SizedBox(height: 8),
                          for (final event in handledEvents) ...[
                            _HandledEventRow(
                              event: event,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ],
                        if (handledExpenses.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          const Text('Recently handled expenses', style: AppText.caption),
                          const SizedBox(height: 8),
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
        ),
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
            accent: AppColors.indigo,
            onTap: onSetBudget,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.description_outlined,
            label: isGenerating ? 'Generating...' : 'Reports',
            accent: AppColors.sageTeal,
            onTap: onGenerateReports,
            loading: isGenerating,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionTile(
            icon: Icons.bar_chart_outlined,
            label: 'Analytics',
            accent: AppColors.brick,
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
  final Color accent;
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border, width: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            )
                : Icon(icon, color: accent, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
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
    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.adviserApprovalNote?.isNotEmpty == true)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.sageTealTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 13, color: AppColors.sageTealText),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Adviser-approved · "${event.adviserApprovalNote}"',
                          style: const TextStyle(fontFamily: AppText.bodyFamily, fontSize: 11, color: AppColors.sageTealText),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(event.title, style: AppText.cardTitle),
              const SizedBox(height: 2),
              Text('${event.org} · ${event.date}', style: AppText.caption),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    event.budget,
                    style: const TextStyle(
                      fontFamily: AppText.monoFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      color: AppColors.ink,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text('Review', style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.indigo)),
                      Icon(Icons.chevron_right, size: 16, color: AppColors.indigo),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
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
    final isRejected = event.status == EventApprovalStatus.rejected;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F5F1),
          border: Border.all(color: AppColors.border, width: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isRejected ? Icons.cancel_outlined : Icons.check_circle_outline,
              size: 15,
              color: isRejected ? AppColors.brick : AppColors.inkFaint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${event.title} · ${event.statusLabel}',
                style: AppText.caption,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, size: 14, color: AppColors.inkFaint),
          ],
        ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F1),
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isRejected ? Icons.cancel_outlined : Icons.check_circle_outline,
            size: 15,
            color: isRejected ? AppColors.brick : AppColors.inkFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${expense.vendor} · ₱${expense.amount.toStringAsFixed(2)} · ${isRejected ? 'Rejected' : 'Approved'}',
              style: AppText.caption,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      child: Text(text, style: AppText.caption),
    );
  }
}