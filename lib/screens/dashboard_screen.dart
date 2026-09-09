import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/financial_overview.dart';
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
                subtitle: 'CITE Dept Officer',
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
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
                        MetricCard(
                          label: 'Total budget allocated',
                          value: '₱${app.totalAllocated.toStringAsFixed(2)}',
                          icon: Icons.account_balance_wallet_outlined,
                          iconColor: AppColors.indigo,
                        ),
                        const SizedBox(height: 10),
                        ExpendedCard(
                          expended: app.totalExpended,
                          allocated: app.totalAllocated,
                        ),
                        const SizedBox(height: 10),
                        RemainingBalanceCard(balance: app.remainingBalance),
                        const SizedBox(height: 16),
                        AllocationVsActualCard(
                          budgets: app.categoryBudgets,
                          spend: app.spendByCategory,
                        ),
                        const SizedBox(height: 10),
                        ExpenseDistributionCard(spendByCategory: app.spendByCategory),
                        const SizedBox(height: 16),
                        const _QuickReports(),
                        const SizedBox(height: 16),
                        const Text('Recent activity', style: AppText.caption),
                        const SizedBox(height: 8),
                        _RecentExpensesList(entries: app.expenses),
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
  final List<ExpenseEntry> entries;
  const _RecentExpensesList({required this.entries});

  Color _statusColor(ExpenseStatus s) => switch (s) {
    ExpenseStatus.approved => AppColors.sageTealText,
    ExpenseStatus.rejected => AppColors.brick,
    ExpenseStatus.pending => AppColors.marigoldText,
  };

  Color _statusBg(ExpenseStatus s) => switch (s) {
    ExpenseStatus.approved => AppColors.sageTealTint,
    ExpenseStatus.rejected => const Color(0xFFFBEAE7),
    ExpenseStatus.pending => AppColors.marigoldTint,
  };

  String _statusLabel(ExpenseStatus s) => switch (s) {
    ExpenseStatus.approved => 'Approved',
    ExpenseStatus.rejected => 'Rejected',
    ExpenseStatus.pending => 'Pending',
  };

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
                  Expanded(
                    child: Text(
                      '${entries[i].vendor} · -₱${entries[i].amount.toStringAsFixed(2)}',
                      style: AppText.body.copyWith(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusBg(entries[i].status),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabel(entries[i].status),
                      style: TextStyle(
                        fontFamily: AppText.bodyFamily,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: _statusColor(entries[i].status),
                      ),
                    ),
                  ),
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