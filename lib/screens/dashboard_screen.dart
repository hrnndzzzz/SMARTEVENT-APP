import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'expense_detail_screen.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/financial_overview.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';
import 'reports_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Consumer<AppState>(
                  builder: (context, app, _) {
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
                        ExpenseDistributionCard(spendByCategory: app.spendByCategory),
                        const SizedBox(height: 20),
                        const _QuickReports(),
                        const SizedBox(height: 20),
                        BrutSectionTitle(
                          'Recent activity',
                          aside: app.expenses.isEmpty
                              ? null
                              : MonoLabel('${app.expenses.length} logged'),
                        ),
                        const SizedBox(height: 10),
                        _RecentExpensesList(entries: app.expenses),
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

class _QuickReports extends StatelessWidget {
  const _QuickReports();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BrutSectionTitle('Reports'),
        const SizedBox(height: 10),
        BrutButton(
          label: 'Open reports & export',
          icon: Icons.insert_chart_outlined,
          tone: BrutTone.neutral,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ReportsScreen()),
          ),
        ),
      ],
    );
  }
}

class _RecentExpensesList extends StatelessWidget {
  final List<ExpenseEntry> entries;
  const _RecentExpensesList({required this.entries});

  static BrutTone _tone(ExpenseStatus s) => switch (s) {
        ExpenseStatus.approved => BrutTone.mint,
        ExpenseStatus.rejected => BrutTone.coral,
        ExpenseStatus.pending => BrutTone.sun,
      };

  static String _label(ExpenseStatus s) => switch (s) {
        ExpenseStatus.approved => 'Approved',
        ExpenseStatus.rejected => 'Rejected',
        ExpenseStatus.pending => 'Pending',
      };

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const BrutEmptyState(
        title: 'No expenses logged yet',
        hint: 'Expenses appear here as soon as a treasurer records one.',
        icon: Icons.receipt_long_outlined,
      );
    }

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          BrutListRow(
            title: entries[i].vendor,
            meta: '-₱${entries[i].amount.toStringAsFixed(2)}',
            marker: BrutIconTile(
              icon: entries[i].isFlagged
                  ? Icons.flag_outlined
                  : Icons.receipt_outlined,
              // A flag has to be visible in the list, not only on the
              // detail screen.
              tone: entries[i].isFlagged ? BrutTone.sun : BrutTone.neutral,
              size: 32,
            ),
            trailing: BrutBadge(
              label: _label(entries[i].status),
              tone: _tone(entries[i].status),
            ),
            // The row is the way into the full record: line items, the
            // OCR reading, any flag, and purchase completion.
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ExpenseDetailScreen(expense: entries[i]),
              ),
            ),
          ),
          if (i != entries.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}
