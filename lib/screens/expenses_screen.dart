import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/expense_review.dart';
import 'expense_detail_screen.dart';
import '../theme/peso.dart';

/// Expenses, with the ones waiting on a decision at the top.
///
/// This used to live halfway down each role's dashboard, which meant the
/// review queue was somewhere you scrolled past on the way to a chart.
/// It belongs with the money.
///
/// A reviewer sees the pending ones as cards that open the decision; for
/// everyone else the same records are a list to read. The API refuses a
/// decision from the person who recorded it either way — this only
/// avoids offering a button that is certain to fail.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadExpenses();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final role = app.currentRole;
    final canReview = role?.canReview ?? false;
    final pending = app.pendingExpenses;
    final handled = app.expenses
        .where((e) => e.status != ExpenseStatus.pending)
        .toList();

    return BrutScreen(
      topBar: AppHeader(
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.section),
          const Text('Expenses', style: AppText.display),
          const SizedBox(height: 6),
          Text(
            canReview
                ? 'Tap a pending one to approve or reject it.'
                : 'Everything recorded, and where each one got to.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppLayout.section),

          if (app.expensesLoad.isLoading && app.expenses.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: BrutSpinner(),
              ),
            )
          else if (app.expensesLoad.hasFailed && app.expenses.isEmpty)
            BrutRetry(
              title: 'Could not load expenses',
              message: app.expensesLoad.error,
              sessionExpired: app.expensesLoad.sessionExpired,
              onRetry: app.loadExpenses,
            )
          else if (app.expenses.isEmpty)
            const Center(
              child: BrutEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Nothing recorded yet',
                hint:
                    'Expenses appear here as soon as a treasurer '
                    'records one.',
              ),
            )
          else ...[
            if (pending.isNotEmpty) ...[
              BrutSectionTitle(
                canReview ? 'Waiting on you' : 'Awaiting review',
                aside: MonoLabel('${pending.length}'),
              ),
              const SizedBox(height: AppLayout.between),
              for (var i = 0; i < pending.length; i++) ...[
                if (canReview)
                  ExpensePendingCard(
                    expense: pending[i],
                    reviewerRole: role == UserRole.adviser
                        ? 'Adviser'
                        : 'Admin',
                  )
                else
                  _Row(expense: pending[i]),
                if (i != pending.length - 1)
                  const SizedBox(height: AppLayout.tight),
              ],
              const SizedBox(height: AppLayout.section),
            ],
            if (handled.isNotEmpty) ...[
              BrutSectionTitle(
                'Decided',
                aside: MonoLabel('${handled.length}'),
              ),
              const SizedBox(height: AppLayout.between),
              for (var i = 0; i < handled.length; i++) ...[
                _Row(expense: handled[i]),
                if (i != handled.length - 1)
                  const SizedBox(height: AppLayout.tight),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.expense});

  final ExpenseEntry expense;

  @override
  Widget build(BuildContext context) {
    final tone = expenseStatusTone(expense.status);
    final label = switch (expense.status) {
      ExpenseStatus.approved => 'Approved',
      ExpenseStatus.rejected => 'Rejected',
      ExpenseStatus.pending => 'Pending',
    };

    return BrutListRow(
      title: expense.vendor,
      // Amount first: the row is narrow next to the status badge, and
      // the figure is the part worth reading if only one survives.
      meta: '${peso(expense.amount)} · ${expense.category}',
      marker: BrutIconTile(
        icon: expense.isFlagged ? Icons.flag_outlined : Icons.receipt_outlined,
        tone: expense.isFlagged ? BrutTone.sun : tone,
        size: 32,
      ),
      trailing: BrutBadge(label: label, tone: tone),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExpenseDetailScreen(expense: expense),
        ),
      ),
    );
  }
}
