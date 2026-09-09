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

class AdviserDashboardScreen extends StatelessWidget {
  const AdviserDashboardScreen({super.key});

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
                subtitle: 'Faculty Adviser',
                subtitleBg: AppColors.sageTealTint,
                subtitleColor: AppColors.sageTealText,
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
                    final pendingEvents = app.pendingAdviserEvents;
                    final handledEvents = app.adviserHandledEvents;
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
                        const SizedBox(height: 18),
                        Text('Pending events (${pendingEvents.length})', style: AppText.cardTitle),
                        const SizedBox(height: 4),
                        const Text('Tap a request to review and decide.', style: AppText.caption),
                        const SizedBox(height: 10),
                        if (pendingEvents.isEmpty)
                          const _EmptyState(text: 'No pending events. All caught up.')
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
                            ExpensePendingCard(expense: expense, reviewerRole: 'Adviser'),
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.marigoldTint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Event Proposal',
                      style: TextStyle(
                        fontFamily: AppText.bodyFamily,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.marigoldText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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