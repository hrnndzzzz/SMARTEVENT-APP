import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

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
                initials: 'SA',
                subtitle: 'System Administrator',
                subtitleBg: const Color(0xFFE8ECF3),
                subtitleColor: AppColors.indigo,
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountScreen(
                      initials: 'SA',
                      name: 'Admin User',
                      role: 'System Administrator',
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
                    _QuickActionsGrid(),
                    SizedBox(height: 18),
                    Text('Pending approvals', style: AppText.cardTitle),
                    SizedBox(height: 10),
                    _ApprovalCard(
                      title: 'Leadership Summit 2026 — Budget Proposal',
                      org: 'Engineering Soc.',
                      amount: '₱8,200.00',
                    ),
                    SizedBox(height: 10),
                    _ApprovalCard(
                      title: 'CITE Sports Fest — Cash Advance',
                      org: 'CITE Student Council',
                      amount: '₱1,500.00',
                    ),
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

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: const [
        _ActionTile(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Set Category Budget',
          accent: AppColors.indigo,
        ),
        _ActionTile(
          icon: Icons.fact_check_outlined,
          label: 'Approve / Reject Requests',
          accent: AppColors.marigold,
        ),
        _ActionTile(
          icon: Icons.description_outlined,
          label: 'Generate Reports',
          accent: AppColors.sageTeal,
        ),
        _ActionTile(
          icon: Icons.bar_chart_outlined,
          label: 'View Analytics',
          accent: AppColors.brick,
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _ActionTile({required this.icon, required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: accent, size: 20),
          Text(
            label,
            style: AppText.body.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final String title;
  final String org;
  final String amount;

  const _ApprovalCard({required this.title, required this.org, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.cardTitle),
            const SizedBox(height: 4),
            Text(org, style: AppText.caption),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  amount,
                  style: const TextStyle(
                    fontFamily: AppText.monoFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        side: const BorderSide(color: AppColors.brick, width: 0.8),
                        foregroundColor: AppColors.brick,
                      ),
                      child: const Text('Reject', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      ),
                      child: const Text('Approve', style: TextStyle(fontSize: 12)),
                    ),
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