import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../theme/peso.dart';
import '../widgets/module_band.dart';
import '../widgets/stat_grid.dart';
import '../theme/module_identity.dart';

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

/// How to order the flagged list.
///
/// There is no severity on a flagged expense — only a reason, as free
/// text — so nothing here pretends to rank by how bad something is.
/// These sort by what the record actually holds. A real severity would
/// have to come from the backend.
enum FlagOrder {
  newest('Newest'),
  largest('Largest'),
  reason('By reason');

  const FlagOrder(this.label);

  final String label;

  /// A copy, ordered. The list it is given is left alone.
  List<RemoteExpense> apply(List<RemoteExpense> flagged) {
    final sorted = [...flagged];
    switch (this) {
      case FlagOrder.newest:
        sorted.sort((a, b) {
          final left = a.expenseDate ?? a.createdAt;
          final right = b.expenseDate ?? b.createdAt;
          return right.compareTo(left);
        });
      case FlagOrder.largest:
        sorted.sort((a, b) => b.amount.compareTo(a.amount));
      case FlagOrder.reason:
        // Same reasons together, and the ones with no reason last
        // rather than first, where they would push the rest down.
        sorted.sort((a, b) {
          final left = a.flagReason ?? '\uffff';
          final right = b.flagReason ?? '\uffff';
          return left.compareTo(right);
        });
    }
    return sorted;
  }
}

class _RiskScreenState extends State<RiskScreen> {
  FlagOrder _order = FlagOrder.newest;

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
    final flagged = _order.apply(app.flaggedExpenses);

    return BrutScreen(
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      // One scroll for the whole page. The band, the figures and the
      // filters used to be fixed while the list scrolled inside what
      // was left, so the list was read through a letterbox and a pull
      // on the top half did nothing. See inventory_screen.dart.
      onRefresh: () => app.refreshList(app.loadFlaggedExpenses),
      bottomPadding: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ModuleBand(
            module: Module.flagged,
            subtitle: 'A flag is a prompt to look, not a finding.',
          ),
          const SizedBox(height: AppLayout.between),

          // What is flagged, in figures, before the list of it.
          //
          // The normal state of this screen is empty, and empty it was
          // a coloured band and then nothing at all until a dashed box
          // floating in the middle of the page. These four are true at
          // zero as well as at ten, so the screen says something either
          // way.
          _Figures(flagged: flagged),
          const SizedBox(height: AppLayout.between),

          if (flagged.length > 1) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final order in FlagOrder.values)
                    IntrinsicWidth(
                      child: BrutChip(
                        label: order.label,
                        selected: order == _order,
                        onTap: () => setState(() => _order = order),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          switch (load) {
            _ when load.isLoading && flagged.isEmpty => const SizedBox(
              height: 240,
              child: Center(child: BrutSpinner()),
            ),
            _ when load.hasFailed && flagged.isEmpty => BrutRetry(
              title: 'Could not load flagged expenses',
              message: load.error,
              sessionExpired: load.sessionExpired,
              onRetry: app.loadFlaggedExpenses,
            ),
            _ when flagged.isEmpty => const _NothingFlagged(),
            _ => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final expense in flagged) ...[
                  _FlaggedCard(expense: expense),
                  const SizedBox(height: 10),
                ],
                const _CriteriaCard(),
              ],
            ),
          },
        ],
      ),
    );
  }
}

/// How much is flagged, and how much of it is a reading that disagrees.
///
/// Every figure here is counted off the records themselves. The reason
/// on a flag is free text from the backend, so nothing tries to sort
/// flags into kinds — that would be guessing at a string. The one kind
/// the record actually states is the OCR mismatch, which is a field.
class _Figures extends StatelessWidget {
  const _Figures({required this.flagged});

  final List<RemoteExpense> flagged;

  @override
  Widget build(BuildContext context) {
    final mismatched = flagged.where((e) => e.ocrAmountDiffers).length;
    final total = flagged.fold<double>(0, (sum, e) => sum + e.amount);
    final largest = flagged.isEmpty
        ? 0.0
        : flagged.map((e) => e.amount).reduce((a, b) => a > b ? a : b);

    return StatGrid(
      cells: [
        StatCell(
          label: 'Flagged',
          value: '${flagged.length}',
          tone: flagged.isEmpty ? BrutTone.mint : BrutTone.sun,
          hint: flagged.isEmpty ? 'All clear' : 'Waiting to be looked at',
        ),
        StatCell(
          label: 'Receipt mismatch',
          value: '$mismatched',
          tone: mismatched == 0 ? BrutTone.neutral : BrutTone.coral,
          hint: mismatched == 0 ? null : 'Read amount differs',
        ),
        StatCell(
          label: 'Value flagged',
          value: peso(total, decimals: 0),
          tone: BrutTone.neutral,
        ),
        StatCell(
          label: 'Largest',
          value: peso(largest, decimals: 0),
          tone: BrutTone.neutral,
        ),
      ],
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
                peso(expense.amount),
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

/// The normal state of this screen.
///
/// It used to be one dashed box centred in an otherwise empty page,
/// which is a lot of screen spent on the word "nothing". What is
/// missing when there is nothing to list is the thing that makes the
/// screen interpretable at all: what a flag *is*. That card was
/// appended to the end of the list, so it appeared only when there were
/// flags to explain — exactly when you need it least.
class _NothingFlagged extends StatelessWidget {
  const _NothingFlagged();

  @override
  Widget build(BuildContext context) {
    // A Column, not a ListView: the page scrolls as one now, and a
    // scroller nested in a scroller has no height to be.
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutEmptyState(
          icon: Icons.verified_outlined,
          title: 'Nothing flagged',
          hint:
              'No expense has tripped a check. This is the normal state — it '
              'does not mean nothing has been reviewed.',
        ),
        _CriteriaCard(),
      ],
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
