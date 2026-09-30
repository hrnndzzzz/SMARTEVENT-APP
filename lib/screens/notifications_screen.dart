import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The signed-in user's notification inbox.
///
/// Tapping one marks it read. There is no mark-all-read and no delete,
/// because the backend has neither — and a button that silently does
/// nothing is worse than its absence.
///
/// The backend currently raises these for registration confirmations only,
/// so an empty inbox is the normal state rather than a sign of breakage.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadNotices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.noticesLoad;

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
                  const SizedBox(width: 10),
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
                  if (app.unreadNoticeCount > 0)
                    Text('${app.unreadNoticeCount} unread',
                        style: AppText.caption),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: switch (load) {
                  _ when load.isLoading && app.notices.isEmpty =>
                    const Center(child: CircularProgressIndicator()),
                  _ when load.hasFailed && app.notices.isEmpty => Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(load.error!,
                                style: AppText.caption,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: app.loadNotices,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _ when app.notices.isEmpty => const _Empty(),
                  _ => RefreshIndicator(
                      onRefresh: app.loadNotices,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: app.notices.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _NoticeCard(notice: app.notices[i]),
                      ),
                    ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});

  final AppNotice notice;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: notice.isUnread
          ? () async {
              final messenger = ScaffoldMessenger.of(context);
              final error =
                  await context.read<AppState>().markNoticeRead(notice);
              if (error != null) {
                messenger.showSnackBar(SnackBar(content: Text(error)));
              }
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // Unread stands out; read fades back rather than disappearing.
          color: notice.isUnread ? AppColors.surface : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notice.isUnread ? AppColors.indigoLightTint : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (notice.isUnread) ...[
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5, right: 8),
                    decoration: const BoxDecoration(
                      color: AppColors.indigo,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                Expanded(
                  child: Text(
                    notice.title,
                    style: notice.isUnread
                        ? AppText.cardTitle
                        : AppText.cardTitle.copyWith(color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(notice.body, style: AppText.caption),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _when(notice.createdAt.toLocal()),
                  style: const TextStyle(
                    fontFamily: AppText.bodyFamily,
                    fontSize: 10,
                    color: AppColors.inkFaint,
                  ),
                ),
                if (notice.emailFailed) ...[
                  const SizedBox(width: 8),
                  // The notice itself arrived; only the email did not. Said
                  // plainly so nobody waits for a message that isn't coming.
                  Text(
                    'the matching email could not be sent',
                    style: AppText.caption.copyWith(
                      color: AppColors.marigoldText,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _when(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}'
      '-${at.day.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none, size: 44, color: AppColors.inkFaint),
          SizedBox(height: 14),
          Text('Nothing here', style: AppText.cardTitle),
          SizedBox(height: 6),
          SizedBox(
            width: 280,
            child: Text(
              'Notifications appear when the system has something to tell '
              'you, such as a registration being confirmed.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
