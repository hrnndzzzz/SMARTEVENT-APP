import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import '../widgets/app_header.dart';
import 'categories_screen.dart';
import 'expenses_screen.dart';
import 'income_screen.dart';
import 'receipts_screen.dart';
import 'scanner_screen.dart';
import '../theme/peso.dart';

/// Everything about money, in one place.
///
/// These four used to be four separate destinations in a radial menu
/// alongside seven others. They belong together: one of them records
/// spending, one reviews the proof, one records what came in, and one
/// sets the ceiling. The strip at the top is the same four figures the
/// dashboard shows, so you can see where you stand before choosing.
class MoneyScreen extends StatelessWidget {
  const MoneyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final canRecord = app.mayRecordFinance;

    return BrutScreen(
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.section),
          const Text('Money', style: AppText.display),
          const SizedBox(height: AppLayout.section),
          MoneyFigures(
            app: app,
            onPending: () => _go(context, const ExpensesScreen()),
          ),
          const SizedBox(height: AppLayout.tight),
          _UsedBar(app: app),
          const SizedBox(height: AppLayout.section),
          const BrutSectionTitle('What do you need?'),
          const SizedBox(height: AppLayout.between),
          _Tile(
            icon: Icons.fact_check_outlined,
            title: 'Expenses',
            blurb: app.pendingExpenses.isEmpty
                ? 'Everything recorded, and where each one got to.'
                : 'Some are waiting on a decision.',
            tone: app.pendingExpenses.isEmpty ? BrutTone.brand : BrutTone.sun,
            count: app.pendingExpenses.length,
            onTap: () => _go(context, const ExpensesScreen()),
          ),
          const SizedBox(height: AppLayout.tight),
          _Tile(
            icon: Icons.document_scanner_outlined,
            title: 'Record an expense',
            blurb: canRecord
                ? 'Scan the receipt, check what was read, save.'
                : 'A Treasurer records these. You can see them here.',
            tone: BrutTone.orange,
            onTap: () => _go(context, const ScannerScreen()),
          ),
          const SizedBox(height: AppLayout.tight),
          _Tile(
            icon: Icons.receipt_long_outlined,
            title: 'Receipts',
            blurb: 'Proof of spending, and anything that looks duplicated.',
            tone: BrutTone.sun,
            count: app.receipts.length,
            onTap: () => _go(context, const ReceiptsScreen()),
          ),
          const SizedBox(height: AppLayout.tight),
          _Tile(
            icon: Icons.savings_outlined,
            title: 'Income',
            blurb: 'Fees, sponsorships and donations, by where they came from.',
            tone: BrutTone.mint,
            count: app.incomes.length,
            onTap: () => _go(context, const IncomeScreen()),
          ),
          const SizedBox(height: AppLayout.tight),
          _Tile(
            icon: Icons.folder_outlined,
            title: 'Budget categories',
            blurb: 'What is allocated, and what is left in each.',
            tone: BrutTone.brand,
            count: app.categories.length,
            onTap: () => _go(context, const CategoriesScreen()),
          ),
        ],
      ),
    );
  }

  void _go(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

/// The four figures, as four boxes.
///
/// They were one orange card split by hairlines, which gave equal weight
/// to a number that is only context (what was allocated) and a number
/// that is a warning (how little is left). Separate boxes, each coloured
/// by what it is actually saying.
///
/// Spent and Left are not inflow and outflow. Inflow and outflow are
/// money arriving and money leaving; these are budget consumed and
/// budget remaining, which is a different question and the one a
/// treasurer is asking here.
class MoneyFigures extends StatelessWidget {
  const MoneyFigures({super.key, required this.app, required this.onPending});

  final AppState app;

  /// Pending is a queue, so it goes somewhere. The others are totals.
  final VoidCallback onPending;

  /// Green while there is room, amber as it tightens, red when it is
  /// nearly gone. The thresholds are the same ones the progress bar on
  /// this screen already uses, so the two never disagree.
  static BrutTone toneForUsed(double fraction) => switch (fraction) {
    >= 0.9 => BrutTone.coral,
    >= 0.7 => BrutTone.sun,
    _ => BrutTone.mint,
  };

  @override
  Widget build(BuildContext context) {
    final allocated = app.totalAllocated;
    final spent = app.totalExpended;
    final used = allocated == 0 ? 0.0 : (spent / allocated).clamp(0.0, 1.0);
    final pending = app.pendingExpenses.length;

    final cells = <_Figure>[
      _Figure(
        label: 'Allocated',
        value: peso(allocated, decimals: 0),
        // Context, not a verdict: what was given, before any judgement
        // about how it is going.
        tone: BrutTone.neutral,
      ),
      _Figure(
        label: 'Spent',
        value: peso(spent, decimals: 0),
        tone: toneForUsed(used),
      ),
      _Figure(
        label: 'Left',
        value: peso(app.remainingBalance, decimals: 0),
        tone: toneForUsed(used),
      ),
      _Figure(
        label: 'Pending',
        value: '$pending',
        tone: pending == 0 ? BrutTone.neutral : BrutTone.sun,
        onTap: onPending,
        hint: pending == 0 ? null : 'Waiting on a decision',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < 2; row++) ...[
          // IntrinsicHeight, because stretching a Row's children needs a
          // height to stretch to and this sits in a scrollable, where
          // there is none. Without it the row cannot lay out and the
          // screen comes up with the first two figures and nothing else.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cells[row * 2]),
                const SizedBox(width: 10),
                Expanded(child: cells[row * 2 + 1]),
              ],
            ),
          ),
          if (row == 0) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// One of the four.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.tone,
    this.onTap,
    this.hint,
  });

  final String label;
  final String value;
  final BrutTone tone;
  final VoidCallback? onTap;

  /// A second line, when the figure needs one.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: tone,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: MonoLabel(label, fontSize: 10)),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 16, color: context.palette.ink),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppText.moneyLarge.copyWith(fontSize: 22),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hint case final line?) ...[
            const SizedBox(height: 4),
            Text(line, style: AppText.caption.copyWith(fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.tone,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String title;
  final String blurb;
  final BrutTone tone;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      radius: AppRadius.rowAll,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          BrutIconTile(icon: icon, tone: tone, size: 40),
          const SizedBox(width: AppLayout.between),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppText.cardTitle.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(blurb, style: AppText.caption),
              ],
            ),
          ),
          // A zero here would mean "nothing yet", which the row already
          // says. It would also look identical to "not loaded".
          if (count != null && count! > 0) ...[
            const SizedBox(width: AppLayout.tight),
            BrutBadge(label: '$count', tone: tone, mono: true),
          ],
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }
}

/// How much of the allocation has gone, as a bar.
///
/// The strip above says allocated, spent and left as three figures you
/// have to divide in your head. This is the same fact in the shape of
/// it: the one thing people want off this screen at a glance.
class _UsedBar extends StatelessWidget {
  const _UsedBar({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final allocated = app.totalAllocated;
    final used = allocated <= 0
        ? 0.0
        : (app.totalExpended / allocated).clamp(0.0, 1.0);
    final over = used >= 1;

    return BrutCard(
      radius: AppRadius.rowAll,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: MonoLabel('Budget used')),
              Text(
                '${(used * 100).round()}%',
                style: AppText.number.copyWith(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          BrutProgressBar(
            value: used,
            tone: over ? BrutTone.coral : BrutTone.orange,
          ),
        ],
      ),
    );
  }
}
