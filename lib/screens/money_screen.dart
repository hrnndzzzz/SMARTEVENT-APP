import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'categories_screen.dart';
import 'income_screen.dart';
import 'receipts_screen.dart';
import 'scanner_screen.dart';

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
    final canRecord = app.currentRole?.canRecordFinance ?? false;

    return BrutScreen(
      header: BrutHeader(
        eyebrow: 'Area',
        title: 'Money',
        tone: BrutTone.orange,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Strip(app: app),
          const SizedBox(height: AppLayout.section),
          const BrutSectionTitle('What do you need?'),
          const SizedBox(height: AppLayout.between),
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

  void _go(BuildContext context, Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => screen));
}

/// Four figures, split by rules, the way a summary card reads.
class _Strip extends StatelessWidget {
  const _Strip({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final figures = [
      ('Allocated', '₱${app.totalAllocated.toStringAsFixed(0)}'),
      ('Spent', '₱${app.totalExpended.toStringAsFixed(0)}'),
      ('Left', '₱${app.remainingBalance.toStringAsFixed(0)}'),
      ('Pending', '${app.pendingExpenses.length}'),
    ];

    return BrutCard(
      tone: BrutTone.sun,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: Row(
        children: [
          for (var i = 0; i < figures.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  Text(
                    figures[i].$2,
                    style: AppText.moneyLarge.copyWith(fontSize: 17),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  MonoLabel(figures[i].$1, fontSize: 9),
                ],
              ),
            ),
            if (i != figures.length - 1)
              Container(width: 2, height: 36, color: context.palette.ink),
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
          if (count != null) ...[
            const SizedBox(width: AppLayout.tight),
            BrutBadge(label: '$count', tone: tone, mono: true),
          ],
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }
}
