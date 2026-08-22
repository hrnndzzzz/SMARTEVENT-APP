import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

class RiskScreen extends StatelessWidget {
  const RiskScreen({super.key});

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
              const SizedBox(height: 12),
              const Text(
                'Event Spending Risk',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                  color: AppColors.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Flags events where spending has moved outside the usual range.',
                style: AppText.caption,
              ),
              const SizedBox(height: 16),
              const _AlertBanner(),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: const [
                    Text('Active event flags', style: AppText.cardTitle),
                    SizedBox(height: 10),
                    _RiskEventCard(
                      title: 'Leadership Summit 2026',
                      level: 'Medium',
                      levelColor: AppColors.marigold,
                      levelBg: Color(0xFFF0EAD9),
                      levelTextColor: AppColors.marigoldText,
                      detailLabel: 'Catering spend vs. category average',
                      detailValue: '+18%',
                    ),
                    SizedBox(height: 10),
                    _RiskEventCard(
                      title: 'CITE Sports Fest',
                      level: 'Low',
                      levelColor: AppColors.sageTeal,
                      levelBg: AppColors.sageTealTint,
                      levelTextColor: AppColors.sageTealText,
                      detailLabel: 'Catering spend vs. category average',
                      detailValue: '+4%',
                    ),
                    SizedBox(height: 18),
                    Text('Flag criteria', style: AppText.cardTitle),
                    SizedBox(height: 10),
                    _CriteriaCard(),
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

class _AlertBanner extends StatelessWidget {
  const _AlertBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brick,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Flag detected',
                  style: TextStyle(
                    fontFamily: AppText.headerFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '"Annual IT Night" catering spend is 32% above the category '
                'average for similar events. Flagged for officer review.',
            style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 12, color: Colors.white, height: 1.4),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white, width: 0.8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Review Details', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskEventCard extends StatelessWidget {
  final String title;
  final String level;
  final Color levelColor;
  final Color levelBg;
  final Color levelTextColor;
  final String detailLabel;
  final String detailValue;

  const _RiskEventCard({
    required this.title,
    required this.level,
    required this.levelColor,
    required this.levelBg,
    required this.levelTextColor,
    required this.detailLabel,
    required this.detailValue,
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(title, style: AppText.cardTitle)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: levelBg, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: levelColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$level Risk',
                        style: TextStyle(
                          fontFamily: AppText.bodyFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: levelTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.show_chart, size: 15, color: AppColors.inkMuted),
                const SizedBox(width: 6),
                Expanded(child: Text(detailLabel, style: AppText.caption)),
                Text(
                  detailValue,
                  style: const TextStyle(
                    fontFamily: AppText.monoFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: AppColors.ink,
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

class _CriteriaCard extends StatelessWidget {
  const _CriteriaCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(
              icon: Icons.apartment_outlined,
              title: 'Venue rate changes',
              body: 'A booked venue\'s rate increased since the last event that used it.',
              bottomBorder: true,
            ),
            _row(
              icon: Icons.receipt_long_outlined,
              title: 'Unliquidated advances',
              body: 'A cash advance has passed the 14-day liquidation policy without a report filed.',
              bottomBorder: true,
            ),
            _row(
              icon: Icons.shopping_cart_outlined,
              title: 'Category spend deviation',
              body: 'Spending in a category (catering, supplies, etc.) exceeds this org\'s own historical average by a set threshold.',
              bottomBorder: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String body,
    required bool bottomBorder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: bottomBorder
          ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: const Color(0xFFF4F2EC), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 15, color: AppColors.ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardTitle.copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                Text(body, style: AppText.caption.copyWith(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}