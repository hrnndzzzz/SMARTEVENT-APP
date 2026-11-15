import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/last_change_note.dart';
import '../widgets/module_band.dart';
import '../widgets/stat_grid.dart';
import 'categories_screen.dart';
import 'expenses_screen.dart';
import 'income_screen.dart';
import 'receipts_screen.dart';
import 'scanner_screen.dart';
import '../theme/peso.dart';
import '../theme/module_identity.dart';

/// Everything about money, in one place.
///
/// These four used to be four separate destinations in a radial menu
/// alongside seven others. They belong together: one of them records
/// spending, one reviews the proof, one records what came in, and one
/// sets the ceiling. The strip at the top is the same four figures the
/// dashboard shows, so you can see where you stand before choosing.
class MoneyScreen extends StatefulWidget {
  const MoneyScreen({super.key});

  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  @override
  void initState() {
    super.initState();
    // Receipts and income are not among the lists signing in fetches,
    // and this screen now prints a count of each. A count of a list
    // that was never asked for is a zero that looks like a fact, so
    // the screen fetches what it shows. Expenses and categories come
    // down at sign-in, and the pull-to-refresh above covers the rest.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppState>();
      app.loadReceipts();
      app.loadIncomes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final canRecord = app.mayRecordFinance;

    return BrutScreen(
      onRefresh: context.read<AppState>().refreshAll,
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.between),
          const ModuleBand(
            module: Module.money,
            subtitle: 'Budget, expenses, receipts and income.',
          ),
          const SizedBox(height: AppLayout.tight),
          const LastChangeNote(area: 'finance'),
          const SizedBox(height: AppLayout.section),
          MoneyFigures(
            app: app,
            onPending: () => _go(context, const ExpensesScreen()),
          ),
          const SizedBox(height: AppLayout.tight),
          _UsedBar(app: app),
          const SizedBox(height: AppLayout.section),

          // Recording an expense is the verb on this screen; the four
          // below are places. It was the second of five identical rows,
          // which made the one thing people open Money to *do* look
          // like another thing to go and read.
          if (canRecord) ...[
            BrutButton(
              label: 'Record an expense',
              icon: Icons.document_scanner_outlined,
              tone: BrutTone.orange,
              expand: true,
              onPressed: () => _go(context, const ScannerScreen()),
            ),
            const SizedBox(height: AppLayout.section),
          ],

          const BrutSectionTitle('Where to'),
          const SizedBox(height: AppLayout.between),

          // A 2×2, not five rows down the page.
          //
          // Five full-width rows each said a title, a sentence and a
          // count, which is a lot of words for four destinations and
          // put two of them below the fold. Four squares fit on the
          // screen at once, and the count is the part anyone was
          // reading — so the count is what each square shows.
          _DestinationGrid(
            destinations: [
              _Destination(
                icon: Icons.fact_check_outlined,
                title: 'Expenses',
                count: app.expenses.length,
                // The badge is the pending count, not the total: an
                // expense that has been decided is not asking for
                // anything, and a square that is only ever a running
                // total is a square nobody looks at twice.
                badge: app.pendingExpenses.isEmpty
                    ? null
                    : '${app.pendingExpenses.length} waiting',
                tone: app.pendingExpenses.isEmpty
                    ? BrutTone.brand
                    : BrutTone.sun,
                onTap: () => _go(context, const ExpensesScreen()),
              ),
              _Destination(
                icon: Icons.receipt_long_outlined,
                title: 'Receipts',
                count: app.receipts.length,
                tone: BrutTone.sun,
                onTap: () => _go(context, const ReceiptsScreen()),
              ),
              _Destination(
                icon: Icons.savings_outlined,
                title: 'Income',
                count: app.incomes.length,
                tone: BrutTone.mint,
                onTap: () => _go(context, const IncomeScreen()),
              ),
              _Destination(
                icon: Icons.folder_outlined,
                title: 'Categories',
                count: app.categories.length,
                tone: BrutTone.brand,
                onTap: () => _go(context, const CategoriesScreen()),
              ),
            ],
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

    return StatGrid(
      cells: [
        StatCell(
          label: 'Allocated',
          value: peso(allocated, decimals: 0),
          // Context, not a verdict: what was given, before any judgement
          // about how it is going.
          tone: BrutTone.neutral,
        ),
        StatCell(
          label: 'Spent',
          value: peso(spent, decimals: 0),
          tone: toneForUsed(used),
        ),
        StatCell(
          label: 'Left',
          value: peso(app.remainingBalance, decimals: 0),
          tone: toneForUsed(used),
        ),
        StatCell(
          label: 'Pending',
          value: '$pending',
          tone: pending == 0 ? BrutTone.neutral : BrutTone.sun,
          onTap: onPending,
          hint: pending == 0 ? null : 'Waiting on a decision',
        ),
      ],
    );
  }
}

/// The four places Money leads to, two across.
class _DestinationGrid extends StatelessWidget {
  const _DestinationGrid({required this.destinations});

  final List<_Destination> destinations;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row * 2 < destinations.length; row++) ...[
          if (row > 0) const SizedBox(height: 10),
          // Same reason as StatGrid: stretch needs a height to stretch
          // to, and inside a scrollable there is none until something
          // measures it.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: destinations[row * 2]),
                const SizedBox(width: 10),
                Expanded(
                  child: row * 2 + 1 < destinations.length
                      ? destinations[row * 2 + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One square: what is in there, and how much of it.
class _Destination extends StatelessWidget {
  const _Destination({
    required this.icon,
    required this.title,
    required this.count,
    required this.tone,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final int count;
  final BrutTone tone;
  final VoidCallback onTap;

  /// Shown under the title when something in there wants attention.
  /// Absent is the normal state, and an absent line is quieter than a
  /// line saying nothing is wrong.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              BrutIconTile(icon: icon, tone: tone, size: 36),
              const Spacer(),
              // A zero would mean "nothing yet", which is worth saying
              // here — unlike in a badge, the figure is the point of
              // the square.
              Text(
                '$count',
                style: AppText.moneyLarge.copyWith(fontSize: 22),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(title, style: AppText.cardTitle.copyWith(fontSize: 15)),
          const SizedBox(height: 4),
          // The row reserves the badge's space whether or not it draws
          // one, so a square with nothing waiting is the same height as
          // the one beside it.
          SizedBox(
            height: 20,
            child: badge == null
                ? null
                : BrutBadge(label: badge!, tone: tone, mono: true),
          ),
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
