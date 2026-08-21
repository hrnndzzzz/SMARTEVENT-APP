import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class AdviserDashboardScreen extends StatelessWidget {
  const AdviserDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              const _AdviserHeader(),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: const [
                    _BalanceOverviewCard(),
                    SizedBox(height: 18),
                    Text('Pending requests', style: AppText.cardTitle),
                    SizedBox(height: 10),
                    _RequestCard(
                      title: 'Leadership Summit 2026 — Budget Proposal',
                      org: 'Engineering Soc.',
                      amount: '₱8,200.00',
                      type: 'Budget',
                    ),
                    SizedBox(height: 10),
                    _RequestCard(
                      title: 'CITE Sports Fest — Cash Advance',
                      org: 'CITE Student Council',
                      amount: '₱1,500.00',
                      type: 'Advance',
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Org balance overview', style: AppText.cardTitle),
            const SizedBox(height: 12),
            _row('CITE Student Council', '₱2,850.00'),
            const SizedBox(height: 8),
            _row('Engineering Soc.', '₱1,240.00'),
            const SizedBox(height: 8),
            _row('IT Society', '₱4,910.00'),
          ],
        ),
      ),
    );
  }

  Widget _row(String org, String amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(org, style: AppText.body.copyWith(fontSize: 12)),
        Text(
          amount,
          style: const TextStyle(
            fontFamily: AppText.monoFamily,
            fontWeight: FontWeight.w500,
            fontSize: 13,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  final String title;
  final String org;
  final String amount;
  final String type;

  const _RequestCard({
    required this.title,
    required this.org,
    required this.amount,
    required this.type,
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.marigoldTint,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    type,
                    style: const TextStyle(
                      fontFamily: AppText.bodyFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.marigoldText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: AppText.cardTitle),
            const SizedBox(height: 2),
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