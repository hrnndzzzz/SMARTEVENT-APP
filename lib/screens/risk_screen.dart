import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../theme/peso.dart';

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

    return BrutScreen(
      topBar: AppHeader(
        onBack: () => Navigator.of(context).maybePop(),
      ),
      scrollable: false,
      bottomPadding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Flagged for review', style: AppText.screenTitle),
          const SizedBox(height: 4),
          const Text(
            'Expenses the system noticed something about. A flag is a '
            'prompt to look, not a finding.',
            style: AppText.caption,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: switch (load) {
              _ when load.isLoading && flagged.isEmpty => const Center(
                child: BrutSpinner(),
              ),
              _ when load.hasFailed && flagged.isEmpty => BrutRetry(
                title: 'Could not load flagged expenses',
                message: load.error,
                sessionExpired: load.sessionExpired,
                onRetry: app.loadFlaggedExpenses,
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
    );
  }
}

class _FlaggedCard extends StatelessWidget {
  const _FlaggedCard({required this.expense});

  final RemoteExpense expense;

  @override
  Widget build(BuildContext context) {
    final categoryName =
        context
            .watch<AppState>()
            .categories
            .where((c) => c.id == expense.categoryId)
            .map((c) => c.name)
            .firstOrNull ??
        'Uncategorised';

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrutIconTile(
                icon: Icons.flag_outlined,
                tone: BrutTone.sun,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(expense.description, style: AppText.cardTitle),
                    const SizedBox(height: 2),
                    MonoLabel(categoryName),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${peso(expense.amount)}',
                style: AppText.moneyLarge.copyWith(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BrutInlineMessage(
            tone: BrutTone.sun,
            icon: Icons.search,
            // The backend's own reason, shown verbatim. Nothing is
            // inferred, and no severity is invented.
            text: expense.flagReason?.isNotEmpty == true
                ? expense.flagReason!
                : 'Flagged, but the backend gave no reason.',
          ),
          if (expense.ocrAmountDiffers) ...[
            const SizedBox(height: 8),
            Text(
              'The receipt was read as '
              '${peso(expense.ocrAmount!)}, which differs from '
              'the ${peso(expense.amount)} recorded.',
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
      child: BrutEmptyState(
        icon: Icons.verified_outlined,
        title: 'Nothing flagged',
        hint:
            'No expense has tripped a check. This is the normal state — it '
            'does not mean nothing has been reviewed.',
      ),
    );
  }
}

/// What actually causes a flag, so the list is interpretable.
class _CriteriaCard extends StatelessWidget {
  const _CriteriaCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: BrutCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrutSectionTitle('What causes a flag'),
            const SizedBox(height: 12),
            _line(
              context,
              'A receipt resembles another one — same merchant and '
              'amount, a nearby date.',
            ),
            _line(
              context,
              'The amount read from a receipt differs from the amount '
              'recorded against it.',
            ),
            _line(
              context,
              'An exact duplicate receipt is refused outright and never '
              'reaches this list.',
            ),
            const SizedBox(height: 8),
            const Text(
              'A flag is not an accusation. Resolving one is a reviewer '
              'decision, recorded with a reason.',
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: BoxDecoration(
              color: context.palette.ink,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(text, style: AppText.body.copyWith(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
