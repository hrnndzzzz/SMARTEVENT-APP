import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'inventory_screen.dart';
import 'events_screen.dart';
import 'dashboard_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  void _handleTap(BuildContext context, AppNotification n) {
    context.read<AppState>().markRead(n);
    Widget? target = switch (n.destination) {
      NotifDestination.inventory => const InventoryScreen(),
      NotifDestination.events => const EventsScreen(),
      NotifDestination.dashboard => const DashboardScreen(),
      NotifDestination.none => null,
    };
    if (target != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => target!));
    }
  }

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
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.read<AppState>().markAllNotificationsReadFor(context.read<AppState>().currentRole),
                    child: const Text('Mark all read', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Consumer<AppState>(
                  builder: (context, app, _) {
                    final visible = app.notificationsFor(app.currentRole);
                    if (visible.isEmpty) {
                      return const Center(
                        child: Text('No notifications yet.', style: AppText.caption),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        for (final n in visible) ...[
                          _NotificationTile(
                            notification: n,
                            onTap: () => _handleTap(context, n),
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

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tappable = notification.destination != NotifDestination.none;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            decoration: BoxDecoration(
              color: notification.unread ? AppColors.surface : const Color(0xFFF7F5F1),
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
                  child: Icon(notification.icon, size: 17, color: notification.tagColor),
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
                              notification.title,
                              style: TextStyle(
                                fontFamily: AppText.bodyFamily,
                                fontWeight: notification.unread ? FontWeight.w500 : FontWeight.w400,
                                fontSize: 13,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          if (notification.unread)
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(left: 6, top: 3),
                              decoration: const BoxDecoration(color: AppColors.brick, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(notification.body, style: AppText.caption.copyWith(height: 1.4)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            notification.time,
                            style: const TextStyle(
                              fontFamily: AppText.monoFamily,
                              fontSize: 10,
                              color: AppColors.inkFaint,
                            ),
                          ),
                          if (tappable) ...[
                            const Spacer(),
                            const Icon(Icons.chevron_right, size: 14, color: AppColors.inkFaint),
                          ],
                        ],
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
                color: notification.tagColor,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}