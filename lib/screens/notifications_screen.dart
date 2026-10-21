import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';

/// The signed-in user's notification inbox.
///
/// Tapping one marks it read, and so does swiping it. There is no
/// mark-all-read and no delete, because the backend has neither — and a
/// button that silently does nothing is worse than its absence. That is
/// also why a swipe springs back instead of sliding the row away: the row
/// is still there, it is just read now, and pretending otherwise would be
/// a lie the next refresh exposes.
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

    return BrutScreen(
      header: BrutHeader(
        title: 'Notifications',
        eyebrow: app.unreadNoticeCount > 0
            ? '${app.unreadNoticeCount} unread'
            : null,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      scrollable: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: switch (load) {
          _ when load.isLoading && app.notices.isEmpty => const Center(
            child: BrutSpinner(),
          ),
          _ when load.hasFailed && app.notices.isEmpty => BrutRetry(
            title: 'Could not load notifications',
            message: load.error,
            sessionExpired: load.sessionExpired,
            onRetry: app.loadNotices,
          ),
          _ when app.notices.isEmpty => const _Empty(),
          _ => RefreshIndicator(
            onRefresh: app.loadNotices,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: app.notices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _SwipeToRead(notice: app.notices[i]),
            ),
          ),
        },
      ),
    );
  }
}

/// Swiping an unread notice marks it read. A read one does not move,
/// because there would be nothing for the gesture to do.
class _SwipeToRead extends StatelessWidget {
  const _SwipeToRead({required this.notice});

  final AppNotice notice;

  @override
  Widget build(BuildContext context) {
    if (!notice.isUnread) return _NoticeCard(notice: notice);

    return Dismissible(
      key: ValueKey(notice.id),
      direction: DismissDirection.endToStart,
      background: _SwipeBackground(),
      // Always false: the action is "mark read", not "remove", so the row
      // springs back and redraws as read.
      confirmDismiss: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final error = await context.read<AppState>().markNoticeRead(notice);
        if (error != null) {
          messenger.showSnackBar(SnackBar(content: Text(error)));
        }
        return false;
      },
      child: _NoticeCard(notice: notice),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: context.palette.mintTint,
        borderRadius: AppRadius.cardAll,
        border: context.borderAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mark_email_read_outlined, size: 18),
          const SizedBox(width: 8),
          Text(
            'Mark read',
            style: AppText.buttonLabel.copyWith(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});

  final AppNotice notice;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      // Unread sits on its shadow; read lies flat. The difference is the
      // whole signal, so no dot is needed on top of it.
      shadow: notice.isUnread ? AppShadows.base : AppShadows.none,
      padding: const EdgeInsets.all(14),
      onTap: notice.isUnread
          ? () async {
              final messenger = ScaffoldMessenger.of(context);
              final error = await context.read<AppState>().markNoticeRead(
                notice,
              );
              if (error != null) {
                messenger.showSnackBar(SnackBar(content: Text(error)));
              }
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  notice.title,
                  style: notice.isUnread
                      ? AppText.cardTitle
                      : AppText.cardTitle.copyWith(
                          color: context.palette.subtle,
                        ),
                ),
              ),
              if (notice.isUnread) ...[
                const SizedBox(width: 8),
                const BrutBadge(label: 'New', tone: BrutTone.brand, mono: true),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(notice.body, style: AppText.caption),
          const SizedBox(height: 10),
          Row(
            children: [
              MonoLabel(_when(notice.createdAt.toLocal())),
              if (notice.emailFailed) ...[
                const SizedBox(width: 8),
                // The notice itself arrived; only the email did not. Said
                // plainly so nobody waits for a message that isn't coming.
                const Expanded(
                  child: BrutBadge(
                    label: 'Email not sent',
                    tone: BrutTone.sun,
                    mono: true,
                  ),
                ),
              ],
            ],
          ),
        ],
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
      child: BrutEmptyState(
        icon: Icons.notifications_none,
        title: 'Nothing here',
        hint:
            'Notifications appear when the system has something to tell '
            'you, such as a registration being confirmed.',
      ),
    );
  }
}
