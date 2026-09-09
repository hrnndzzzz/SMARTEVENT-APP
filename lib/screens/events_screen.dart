import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  Color _statusBg(EventApprovalStatus s) => switch (s) {
    EventApprovalStatus.approved => AppColors.sageTealTint,
    EventApprovalStatus.rejected => const Color(0xFFFBEAE7),
    EventApprovalStatus.pendingAdmin => AppColors.marigoldTint,
    EventApprovalStatus.pendingAdviser => const Color(0xFFEDEBE6),
  };

  Color _statusColor(EventApprovalStatus s) => switch (s) {
    EventApprovalStatus.approved => AppColors.sageTealText,
    EventApprovalStatus.rejected => AppColors.brick,
    EventApprovalStatus.pendingAdmin => AppColors.marigoldText,
    EventApprovalStatus.pendingAdviser => AppColors.inkMuted,
  };

  Color _tagColor(EventApprovalStatus s) => switch (s) {
    EventApprovalStatus.approved => AppColors.sageTeal,
    EventApprovalStatus.rejected => AppColors.brick,
    EventApprovalStatus.pendingAdmin => AppColors.marigold,
    EventApprovalStatus.pendingAdviser => AppColors.inkFaint,
  };

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
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
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
                child: Consumer<AppState>(
                  builder: (context, app, _) {
                    if (app.events.isEmpty) {
                      return const Center(
                        child: Text('No events yet. Tap "New" to submit one.', style: AppText.caption),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        for (final event in app.events) ...[
                          _EventCard(
                            event: event,
                            statusBg: _statusBg(event.status),
                            statusColor: _statusColor(event.status),
                            tagColor: _tagColor(event.status),
                          ),
                          const SizedBox(height: 10),
                        ],
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

class _EventCard extends StatelessWidget {
  final EventItem event;
  final Color statusBg;
  final Color statusColor;
  final Color tagColor;

  const _EventCard({
    required this.event,
    required this.statusBg,
    required this.statusColor,
    required this.tagColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(event: event),
        ),
      ),
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
                        event.statusLabel,
                        style: TextStyle(
                          fontFamily: AppText.bodyFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: statusColor,
                        ),
                      ),
                    ),
                    Text(
                      event.date,
                      style: const TextStyle(
                        fontFamily: AppText.monoFamily,
                        fontSize: 11,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(event.title, style: AppText.cardTitle),
                const SizedBox(height: 2),
                Text('${event.org} · ${event.attendees}', style: AppText.caption),
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