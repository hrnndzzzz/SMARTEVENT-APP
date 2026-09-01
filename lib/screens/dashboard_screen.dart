import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

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
                initials: 'SO',
                subtitle: 'QA, Testing',
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountScreen(
                      initials: 'SO',
                      name: 'John Paul Buffe',
                      role: 'QA, Testing',
                    ),
                  ),
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
                        _MetricCard(
                          label: 'Total budget allocated',
                          value: '₱${app.totalAllocated.toStringAsFixed(2)}',
                          icon: Icons.account_balance_wallet_outlined,
                          iconColor: AppColors.indigo,
                        ),
                        const SizedBox(height: 10),
                        _ExpendedCard(
                          expended: app.totalExpended,
                          allocated: app.totalAllocated,
                        ),
                        const SizedBox(height: 10),
                        _RemainingBalanceCard(balance: app.remainingBalance),
                        const SizedBox(height: 16),
                        const _AllocationVsActualCard(),
                        const SizedBox(height: 10),
                         _ExpenseDistributionCard(spendByCategory: app.spendByCategory),
                        const SizedBox(height: 16),
                        const _QuickReports(),
                        const SizedBox(height: 16),
                        const Text('Recent activity', style: AppText.caption),
                        const SizedBox(height: 8),
                        _RecentExpensesList(entries: app.expenseLog),
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

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.caption),
                const SizedBox(height: 4),
                Text(value, style: AppText.moneyLarge),
              ],
            ),
            Icon(icon, color: iconColor, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ExpendedCard extends StatelessWidget {
  final double expended;
  final double allocated;

  const _ExpendedCard({required this.expended, required this.allocated});

  @override
  Widget build(BuildContext context) {
    final progress = allocated == 0 ? 0.0 : (expended / allocated).clamp(0.0, 1.0);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total expended', style: AppText.caption),
                    const SizedBox(height: 4),
                    Text('₱${expended.toStringAsFixed(2)}', style: AppText.moneyLarge),
                  ],
                ),
                const Icon(Icons.receipt_long_outlined, color: AppColors.inkMuted, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: AppColors.trackBg,
                color: progress >= 1.0 ? AppColors.brick : AppColors.indigo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemainingBalanceCard extends StatelessWidget {
  final double balance;
  const _RemainingBalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final isLow = balance < 500;
    final bg = isLow ? const Color(0xFFFBEAE7) : AppColors.sageTealTint;
    final border = isLow ? const Color(0xFFE3B3AA) : AppColors.sageTealBorder;
    final textColor = isLow ? AppColors.brick : AppColors.sageTealText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current remaining balance', style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 12, color: textColor)),
              const SizedBox(height: 4),
              Text(
                '₱${balance.toStringAsFixed(2)}',
                style: TextStyle(
                  fontFamily: AppText.monoFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 21,
                  color: textColor,
                ),
              ),
            ],
          ),
          Icon(isLow ? Icons.warning_amber_rounded : Icons.savings_outlined, color: textColor, size: 20),
        ],
      ),
    );
  }
}

class _AllocationVsActualCard extends StatelessWidget {
  const _AllocationVsActualCard();

  static const List<_MonthBars> _months = [
    _MonthBars('Jan', 0.60, 0.45, false),
    _MonthBars('Feb', 0.70, 0.80, true),
    _MonthBars('Mar', 0.65, 0.35, false),
    _MonthBars('Apr', 0.75, 0.65, false),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Allocation vs actual', style: AppText.cardTitle),
            const SizedBox(height: 14),
            SizedBox(
              height: 90,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _months.map((m) => _buildCluster(m)).toList(),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: _months
                  .map((m) => Expanded(
                child: Text(
                  m.label,
                  textAlign: TextAlign.center,
                  style: AppText.caption,
                ),
              ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            Row(
              children: const [
                _LegendDot(color: AppColors.indigoLightTint, label: 'Allocated'),
                SizedBox(width: 14),
                _LegendDot(color: AppColors.indigo, label: 'Actual'),
                SizedBox(width: 14),
                _LegendDot(color: AppColors.brick, label: 'Over'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCluster(_MonthBars m) {
    const maxHeight = 80.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: m.allocated * maxHeight,
          decoration: const BoxDecoration(
            color: AppColors.indigoLightTint,
            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
        const SizedBox(width: 3),
        Container(
          width: 12,
          height: m.actual * maxHeight,
          decoration: BoxDecoration(
            color: m.isOver ? AppColors.brick : AppColors.indigo,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      ],
    );
  }
}

class _MonthBars {
  final String label;
  final double allocated;
  final double actual;
  final bool isOver;
  const _MonthBars(this.label, this.allocated, this.actual, this.isOver);
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

class _ExpenseDistributionCard extends StatelessWidget {
  final Map<String, double> spendByCategory;
  const _ExpenseDistributionCard({required this.spendByCategory});

  static const _categoryColors = {
    'Equipment': AppColors.indigo,
    'Venue': AppColors.marigold,
    'Catering': AppColors.sageTeal,
    'Marketing': AppColors.inkFaint,
  };

  @override
  Widget build(BuildContext context) {
    final total = spendByCategory.values.fold(0.0, (a, b) => a + b);
    final entries = spendByCategory.entries.where((e) => e.value > 0).toList();

    if (total == 0) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Expense distribution', style: AppText.cardTitle),
              SizedBox(height: 10),
              Text('No expenses logged yet.', style: AppText.caption),
            ],
          ),
        ),
      );
    }

    final colors = <Color>[];
    final stops = <double>[];
    double cursor = 0.0;
    for (final e in entries) {
      final share = e.value / total;
      final color = _categoryColors[e.key] ?? AppColors.inkFaint;
      colors.addAll([color, color]);
      stops.addAll([cursor, cursor + share]);
      cursor += share;
    }
    colors.add(colors.first);
    stops.add(1.0);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Expense distribution', style: AppText.cardTitle),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(colors: colors, stops: stops),
                  ),
                  child: Center(
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '₱${total.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontFamily: AppText.monoFamily,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in entries) ...[
                        _LegendRow(
                          color: _categoryColors[e.key] ?? AppColors.inkFaint,
                          label: '${e.key} (${(e.value / total * 100).round()}%)',
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppText.body.copyWith(fontSize: 12)),
      ],
    );
  }
}

class _QuickReports extends StatefulWidget {
  const _QuickReports();

  @override
  State<_QuickReports> createState() => _QuickReportsState();
}

class _QuickReportsState extends State<_QuickReports> {
  bool _exporting = false;
  bool _downloading = false;

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _exporting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Liquidation report generated — liquidation_q2_2026.pdf')),
    );
  }

  Future<void> _downloadJournal() async {
    setState(() => _downloading = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _downloading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Financial journal downloaded — financial_journal_q2_2026.csv')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick reports', style: AppText.caption),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _exporting ? null : _exportPdf,
          icon: _exporting
              ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: Text(_exporting ? 'Generating...' : 'Export liquidation PDF'),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _downloading ? null : _downloadJournal,
          icon: _downloading
              ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.indigo),
          )
              : const Icon(Icons.download_outlined, size: 16),
          label: Text(_downloading ? 'Downloading...' : 'Download financial journal'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        ),
      ],
    );
  }
}

class _RecentExpensesList extends StatelessWidget {
  final List<String> entries;
  const _RecentExpensesList({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No expenses logged yet.', style: AppText.caption),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(color: Color(0xFFF4F2EC), shape: BoxShape.circle),
                    child: const Icon(Icons.receipt_outlined, size: 14, color: AppColors.ink),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(entries[i], style: AppText.body.copyWith(fontSize: 12))),
                ],
              ),
            ),
            if (i != entries.length - 1) const Divider(height: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}