import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

/// Expenses the backend has flagged for a closer look.
///
/// The endpoint behind this is called "threats", which is not what the
/// screen says. A flag means a receipt looked like another one, or an OCR
/// reading disagreed with the amount entered — reasons to check, not
/// findings. Every number here is the backend's; nothing is inferred and no
/// risk score is invented.
class RiskScreen extends StatefulWidget {
  const RiskScreen({super.key});

  @override
  State<RiskScreen> createState() => _RiskScreenState();
}

class _RiskScreenState extends State<RiskScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadFlaggedExpenses();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.flaggedLoad;
    final flagged = app.flaggedExpenses;

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
              const SizedBox(height: 12),
              const Text(
                'Flagged for review',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                  color: AppColors.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Expenses the system noticed something about. A flag is a '
                'prompt to look, not a finding.',
                style: AppText.caption,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: switch (load) {
                  _ when load.isLoading && flagged.isEmpty =>
                    const Center(child: CircularProgressIndicator()),
                  _ when load.hasFailed && flagged.isEmpty => Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(load.error!,
                                style: AppText.caption,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: app.loadFlaggedExpenses,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _ when flagged.isEmpty => const _NothingFlagged(),
                  _ => RefreshIndicator(
                      onRefresh: app.loadFlaggedExpenses,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: flagged.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => i == flagged.length
                            ? const _CriteriaCard()
                            : _FlaggedCard(expense: flagged[i]),
                      ),
                    ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlaggedCard extends StatelessWidget {
  const _FlaggedCard({required this.expense});

  final RemoteExpense expense;

  @override
  Widget build(BuildContext context) {
    final categoryName = context
            .watch<AppState>()
            .categories
            .where((c) => c.id == expense.categoryId)
            .map((c) => c.name)
            .firstOrNull ??
        'Uncategorised';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.marigold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined,
                  size: 16, color: AppColors.marigoldText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(expense.description, style: AppText.cardTitle),
              ),
              Text('₱${expense.amount.toStringAsFixed(2)}',
                  style: AppText.moneySmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(categoryName, style: AppText.caption),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.marigoldTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              // The backend's own reason, shown verbatim. Nothing is
              // inferred, and no severity is invented.
              expense.flagReason?.isNotEmpty == true
                  ? expense.flagReason!
                  : 'Flagged, but the backend gave no reason.',
              style: AppText.caption.copyWith(color: AppColors.marigoldText),
            ),
          ),
          if (expense.ocrAmountDiffers) ...[
            const SizedBox(height: 8),
            Text(
              'The receipt was read as '
              '₱${expense.ocrAmount!.toStringAsFixed(2)}, which differs from '
              'the ₱${expense.amount.toStringAsFixed(2)} recorded.',
              style: AppText.caption,
            ),
          ],
        ],
      ),
    );
  }
}

class _NothingFlagged extends StatelessWidget {
  const _NothingFlagged();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 44, color: AppColors.inkFaint),
          SizedBox(height: 14),
          Text('Nothing flagged', style: AppText.cardTitle),
          SizedBox(height: 6),
          SizedBox(
            width: 280,
            child: Text(
              'No expense has tripped a check. This is the normal state — it '
              'does not mean nothing has been reviewed.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// What actually causes a flag, so the list is interpretable.
class _CriteriaCard extends StatelessWidget {
  const _CriteriaCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What causes a flag', style: AppText.cardTitle),
          const SizedBox(height: 10),
          _line('A receipt resembles another one — same merchant and amount, '
              'a nearby date.'),
          _line('The amount read from a receipt differs from the amount '
              'recorded against it.'),
          _line('An exact duplicate receipt is refused outright and never '
              'reaches this list.'),
          const SizedBox(height: 8),
          const Text(
            'A flag is not an accusation. Resolving one is a reviewer '
            'decision, recorded with a reason.',
            style: TextStyle(
              fontFamily: AppText.bodyFamily,
              fontSize: 10,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: AppText.caption),
          Expanded(child: Text(text, style: AppText.caption)),
        ],
      ),
    );
  }
}
