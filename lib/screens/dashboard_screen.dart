import 'package:flutter/material.dart';
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
                subtitle: 'CITE Dept Officer',
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountScreen(
                      initials: 'SO',
                      name: 'Juan Dela Cruz',
                      role: 'CITE Dept Officer',
                    ),
                  ),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: const [
                    _MetricCard(
                      label: 'Total budget allocated',
                      value: '₱5,000.00',
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: AppColors.indigo,
                    ),
                    SizedBox(height: 10),
                    _ExpendedCard(),
                    SizedBox(height: 10),
                    _RemainingBalanceCard(),
                    SizedBox(height: 16),
                    _AllocationVsActualCard(),
                    SizedBox(height: 10),
                    _ExpenseDistributionCard(),
                    SizedBox(height: 16),
                    _QuickReports(),
                  ],
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
  const _ExpendedCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total expended', style: AppText.caption),
                    SizedBox(height: 4),
                    Text('₱2,150.00', style: AppText.moneyLarge),
                  ],
                ),
                Icon(Icons.receipt_long_outlined, color: AppColors.inkMuted, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: 0.43,
                minHeight: 5,
                backgroundColor: AppColors.trackBg,
                color: AppColors.indigo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemainingBalanceCard extends StatelessWidget {
  const _RemainingBalanceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.sageTealTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.sageTealBorder, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current remaining balance',
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 12,
                  color: AppColors.sageTealText,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '₱2,850.00',
                style: TextStyle(
                  fontFamily: AppText.monoFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 21,
                  color: AppColors.sageTealText,
                ),
              ),
            ],
          ),
          Icon(Icons.savings_outlined, color: AppColors.sageTealText, size: 20),
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
  const _ExpenseDistributionCard();

  @override
  Widget build(BuildContext context) {
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
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        AppColors.indigo, AppColors.indigo,
                        AppColors.marigold, AppColors.marigold,
                        AppColors.sageTeal, AppColors.sageTeal,
                        AppColors.inkFaint, AppColors.inkFaint,
                        AppColors.indigo,
                      ],
                      stops: [0.0, 0.45, 0.45, 0.75, 0.75, 0.90, 0.90, 1.0, 1.0],
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          '₱2,150',
                          style: TextStyle(
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
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LegendRow(color: AppColors.indigo, label: 'Equipment (45%)'),
                    SizedBox(height: 6),
                    _LegendRow(color: AppColors.marigold, label: 'Venue (30%)'),
                    SizedBox(height: 6),
                    _LegendRow(color: AppColors.sageTeal, label: 'Catering (15%)'),
                    SizedBox(height: 6),
                    _LegendRow(color: AppColors.inkFaint, label: 'Sigaw ni Joseph (10%)'),
                  ],
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