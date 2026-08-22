import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

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
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Events',
                    style: TextStyle(
                      fontFamily: AppText.headerFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 18,
                      color: AppColors.ink,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreateEventScreen()),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    _EventCard(
                      title: 'Annual Fall Hackathon',
                      org: 'Engineering Soc.',
                      date: 'Oct 12-14',
                      statusLabel: 'Active',
                      statusBg: AppColors.sageTealTint,
                      statusColor: AppColors.sageTealText,
                      tagColor: AppColors.sageTeal,
                      detail: '62 attendees',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EventDetailScreen(
                            title: 'Annual Fall Hackathon',
                            org: 'Engineering Soc.',
                            date: 'Oct 12-14, 2026',
                            venue: 'CITE Auditorium',
                            budget: '₱8,200.00',
                            attendees: '62',
                            approvalStep: 3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _EventCard(
                      title: 'Leadership Summit 2026',
                      org: 'CITE Student Council',
                      date: 'Nov 20',
                      statusLabel: 'Under Review',
                      statusBg: AppColors.marigoldTint,
                      statusColor: AppColors.marigoldText,
                      tagColor: AppColors.marigold,
                      detail: 'Awaiting adviser',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EventDetailScreen(
                            title: 'Leadership Summit 2026',
                            org: 'CITE Student Council',
                            date: 'Nov 20, 2026',
                            venue: 'CITE Auditorium',
                            budget: '₱8,200.00',
                            attendees: '120 (expected)',
                            approvalStep: 1,
                          ),
                        ),
                      ),
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

class _EventCard extends StatelessWidget {
  final String title;
  final String org;
  final String date;
  final String statusLabel;
  final Color statusBg;
  final Color statusColor;
  final Color tagColor;
  final String detail;
  final VoidCallback onTap;

  const _EventCard({
    required this.title,
    required this.org,
    required this.date,
    required this.statusLabel,
    required this.statusBg,
    required this.statusColor,
    required this.tagColor,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border, width: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontFamily: AppText.bodyFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: statusColor,
                        ),
                      ),
                    ),
                    Text(
                      date,
                      style: const TextStyle(
                        fontFamily: AppText.monoFamily,
                        fontSize: 11,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(title, style: AppText.cardTitle),
                const SizedBox(height: 2),
                Text('$org · $detail', style: AppText.caption),
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
      ),
    );
  }
}