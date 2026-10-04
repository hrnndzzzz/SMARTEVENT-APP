import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/expense_review.dart';
import '../widgets/financial_overview.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';
import 'event_detail_screen.dart';
import 'events_screen.dart' show eventStatusTone;
import 'expense_detail_screen.dart' show expenseStatusTone;

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
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Consumer<AppState>(
                  builder: (context, app, _) {
                    final pendingEvents = app.pendingAdviserEvents;
                    final handledEvents = app.adviserHandledEvents;
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
                        const SizedBox(height: 18),
                        BrutSectionTitle(
                          'Pending events',
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
                            hint: 'No events are waiting on you.',
                            icon: Icons.task_alt,
                          )
                        else
                          for (final event in pendingEvents) ...[
                            _EventSummaryCard(
                              event: event,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EventDetailScreen(event: event),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        if (pendingExpenses.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          BrutSectionTitle(
                            'Pending expenses',
                            aside: MonoLabel(
                              '${pendingExpenses.length} waiting',
                            ),
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
                              reviewerRole: 'Adviser',
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
                                  builder: (_) =>
                                      EventDetailScreen(event: event),
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
    return BrutCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrutBadge(label: 'Event proposal', tone: BrutTone.sun),
              const Spacer(),
              Text(event.date, style: AppText.moneySmall),
            ],
          ),
          const SizedBox(height: 10),
          Text(event.title, style: AppText.cardTitle),
          const SizedBox(height: 3),
          Text(event.org, style: AppText.caption),
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
