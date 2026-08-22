import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontFamily: AppText.headerFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 18,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: const [
                    _NotificationTile(
                      icon: Icons.warning_amber_rounded,
                      tagColor: AppColors.brick,
                      title: 'Low stock: HDMI Cables (4K 10m)',
                      body: 'Only 1 unit remaining, below minimum threshold.',
                      time: '10 min ago',
                      unread: true,
                    ),
                    SizedBox(height: 10),
                    _NotificationTile(
                      icon: Icons.fact_check_outlined,
                      tagColor: AppColors.marigold,
                      title: 'Pending approval: Leadership Summit 2026',
                      body: 'Budget proposal from Engineering Soc. awaiting your review.',
                      time: '2 hrs ago',
                      unread: true,
                    ),
                    SizedBox(height: 10),
                    _NotificationTile(
                      icon: Icons.event_outlined,
                      tagColor: AppColors.sageTeal,
                      title: 'Upcoming: CITE Sports Fest',
                      body: 'Event starts in 3 days. Final headcount due tomorrow.',
                      time: '5 hrs ago',
                      unread: false,
                    ),
                    SizedBox(height: 10),
                    _NotificationTile(
                      icon: Icons.receipt_long_outlined,
                      tagColor: AppColors.indigo,
                      title: 'Expense logged',
                      body: 'Catering Deposit — Hackathon (₱2,500.00) recorded.',
                      time: 'Yesterday',
                      unread: false,
                    ),
                    SizedBox(height: 10),
                    _NotificationTile(
                      icon: Icons.check_circle_outline,
                      tagColor: AppColors.sageTeal,
                      title: 'Request approved',
                      body: 'Your cash advance for CITE Sports Fest was approved.',
                      time: '2 days ago',
                      unread: false,
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

class _NotificationTile extends StatelessWidget {
  final IconData icon;
  final Color tagColor;
  final String title;
  final String body;
  final String time;
  final bool unread;

  const _NotificationTile({
    required this.icon,
    required this.tagColor,
    required this.title,
    required this.body,
    required this.time,
    required this.unread,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            color: unread ? AppColors.surface : const Color(0xFFF7F5F1),
            border: Border.all(color: AppColors.border, width: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F2EC),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: tagColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontFamily: AppText.bodyFamily,
                              fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                              fontSize: 13,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(left: 6, top: 3),
                            decoration: const BoxDecoration(color: AppColors.brick, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(body, style: AppText.caption.copyWith(height: 1.4)),
                    const SizedBox(height: 6),
                    Text(
                      time,
                      style: const TextStyle(
                        fontFamily: AppText.monoFamily,
                        fontSize: 10,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 12,
          bottom: 12,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
            ),
          ),
        ),
      ],
    );
  }
}