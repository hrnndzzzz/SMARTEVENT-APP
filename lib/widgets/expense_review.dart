import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import '../theme/peso.dart';

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
  final remaining =
      (app.categoryBudgets[expense.category] ?? 0) -
      (app.spendByCategory[expense.category] ?? 0);
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
          Text(
            expense.vendor,
            style: AppText.body.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            '${expense.category} · ${peso(expense.amount)}',
            style: AppText.caption,
          ),
          const SizedBox(height: 10),
          BrutInlineMessage(
            tone: wouldExceed ? BrutTone.coral : BrutTone.mint,
            icon: wouldExceed
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline,
            text: wouldExceed
                ? '${expense.category} only has ${peso(remaining)} left — approving this would exceed it.'
                : '${expense.category} has ${peso(remaining)} remaining. This fits.',
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Feedback (optional)',
            controller: controller,
            maxLines: 3,
            hint: 'Any notes…',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        BrutButton(
          label: 'Reject',
          tone: BrutTone.coral,
          size: BrutSize.small,
          expand: false,
          onPressed: () => Navigator.pop(context, false),
        ),
        BrutButton(
          label: 'Approve',
          tone: BrutTone.mint,
          size: BrutSize.small,
          expand: false,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );

  if (result == null || !context.mounted) return;

  if (result) {
    final error = await app.approveExpense(
      expense,
      reviewerRole: reviewerRole,
      note: controller.text.trim(),
    );
    if (!context.mounted) return;

    if (error != null && onInsufficientBudget != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          action: SnackBarAction(
            label: 'Set Budget',
            onPressed: onInsufficientBudget,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? '${expense.vendor} approved.')),
      );
    }
  } else {
    final error = await app.rejectExpense(
      expense,
      reviewerRole: reviewerRole,
      note: controller.text.trim(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? '${expense.vendor} rejected.')),
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
    return BrutCard(
      onTap: () => showExpenseDecisionDialog(
        context,
        expense,
        reviewerRole: reviewerRole,
        onInsufficientBudget: onInsufficientBudget,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BrutBadge(label: expense.category, tone: BrutTone.sun),
              const Spacer(),
              const BrutBadge(label: 'Pending', tone: BrutTone.sun, dot: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(expense.vendor, style: AppText.cardTitle),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${peso(expense.amount)}',
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
