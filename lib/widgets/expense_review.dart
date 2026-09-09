import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Opens the Approve/Reject dialog for a pending expense. [reviewerRole]
/// should be 'Adviser' or 'Admin' — either can resolve an expense
/// (unlike events, this isn't a two-stage flow). [onInsufficientBudget],
/// if provided, is offered as a quick action in the blocked-approval
/// snackbar (e.g. jumping straight to Set Budget) — only meaningful for
/// Admin, since only Admin can actually change a category's budget.
Future<void> showExpenseDecisionDialog(
    BuildContext context,
    ExpenseEntry expense, {
      required String reviewerRole,
      VoidCallback? onInsufficientBudget,
    }) async {
  final app = context.read<AppState>();
  final remaining = (app.categoryBudgets[expense.category] ?? 0) - (app.spendByCategory[expense.category] ?? 0);
  final wouldExceed = expense.amount > remaining;
  final controller = TextEditingController();

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Review Expense', style: AppText.cardTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(expense.vendor, style: AppText.body.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text('${expense.category} · ₱${expense.amount.toStringAsFixed(2)}', style: AppText.caption),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: wouldExceed ? const Color(0xFFFBEAE7) : AppColors.sageTealTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  wouldExceed ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  size: 15,
                  color: wouldExceed ? AppColors.brick : AppColors.sageTealText,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    wouldExceed
                        ? '${expense.category} only has ₱${remaining.toStringAsFixed(2)} left — approving this would exceed it.'
                        : '${expense.category} has ₱${remaining.toStringAsFixed(2)} remaining. This fits.',
                    style: TextStyle(
                      fontFamily: AppText.bodyFamily,
                      fontSize: 11,
                      color: wouldExceed ? AppColors.brick : AppColors.sageTealText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Feedback (optional)', style: AppText.caption),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Any notes...'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.brick, width: 0.8),
            foregroundColor: AppColors.brick,
          ),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Reject'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Approve'),
        ),
      ],
    ),
  );

  if (result == null || !context.mounted) return;

  if (result) {
    final error = app.approveExpense(expense, reviewerRole: reviewerRole, note: controller.text.trim());
    if (!context.mounted) return;

    if (error != null && onInsufficientBudget != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          action: SnackBarAction(label: 'Set Budget', onPressed: onInsufficientBudget),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? '${expense.vendor} approved.')),
      );
    }
  } else {
    app.rejectExpense(expense, reviewerRole: reviewerRole, note: controller.text.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${expense.vendor} rejected.')),
      );
    }
  }
}

/// Tappable summary card for a pending expense, matching the visual
/// style of the event pending cards used elsewhere.
class ExpensePendingCard extends StatelessWidget {
  final ExpenseEntry expense;
  final String reviewerRole;
  final VoidCallback? onInsufficientBudget;

  const ExpensePendingCard({
    super.key,
    required this.expense,
    required this.reviewerRole,
    this.onInsufficientBudget,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showExpenseDecisionDialog(
        context,
        expense,
        reviewerRole: reviewerRole,
        onInsufficientBudget: onInsufficientBudget,
      ),
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
                    child: Text(
                      expense.category,
                      style: const TextStyle(
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
              Text(expense.vendor, style: AppText.cardTitle),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '₱${expense.amount.toStringAsFixed(2)}',
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