import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class AdviserDashboardScreen extends StatelessWidget {
  const AdviserDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          children: const [
            _AdviserHeader(),
            SizedBox(height: 16),
            _BalanceOverviewCard(),
            SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'View Balances',
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _QuickActionTile(
                    icon: Icons.bar_chart_outlined,
                    label: 'View Analytics',
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
            Text('Pending requests', style: AppText.cardTitle),
            SizedBox(height: 10),
            _RequestCard(
              title: 'Leadership Summit 2026 — Budget Proposal',
              org: 'Engineering Soc.',
              amount: '₱8,200.00',
            ),
            SizedBox(height: 10),
            _RequestCard(
              title: 'CITE Sports Fest — Cash Advance',
              org: 'CITE Student Council',
              amount: '₱1,500.00',
            ),
          ],
        ),
      ),
    );
  }
}

class _AdviserHeader extends StatelessWidget {
  const _AdviserHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 17,
          backgroundColor: AppColors.indigo,
          child: Text(
            'FA',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFamily: AppText.bodyFamily,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SmartEvent', style: AppText.wordmark),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.sageTealTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Faculty Adviser',
                  style: TextStyle(
                    fontFamily: AppText.bodyFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    color: AppColors.sageTealText,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.notifications_none, color: AppColors.indigo, size: 22),
      ],
    );
  }
}

class _BalanceOverviewCard extends StatelessWidget {
  const _BalanceOverviewCard();

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
                'Total balance across organizations',
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 12,
                  color: AppColors.sageTealText,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '₱12,450.00',
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

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;

  const _QuickActionTile({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.indigo),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppText.cardTitle.copyWith(fontSize: 12, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final String title;
  final String org;
  final String amount;

  const _RequestCard({
    required this.title,
    required this.org,
    required this.amount,
  });

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
            const SizedBox(height: 2),
            Text(org, style: AppText.caption),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(amount, style: AppText.moneyLarge.copyWith(fontSize: 16)),
                Row(
                  children: [
                    OutlinedButton(
                      // TODO: wire up to backend once approval API is ready
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brick,
                        side: const BorderSide(color: AppColors.brick, width: 0.5),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('Reject', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      // TODO: wire up to backend once approval API is ready
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
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
