import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// The inbox, as a window rather than a screen.
///
/// Built the same way as the account menu, deliberately: both hang off a
/// control in the top bar, both are things you glance at and dismiss,
/// and two popovers that look and behave differently for no reason is
/// just two things to learn.
///
/// The rule it is built around: **the number on the badge is the length
/// of this list.** If they can disagree the window is worse than
/// nothing, so when the inbox has not been fetched yet it says so rather
/// than showing a shorter list than the badge promised.
abstract final class NotificationMenu {
  static Future<void> show(BuildContext context) {
    // Fetch if what is held does not match what the badge claims. The
    // badge comes from the server's own count; the list is whatever this
    // device has pulled.
    final app = context.read<AppState>();
    if (app.notices.where((n) => n.isUnread).length != app.unreadNoticeCount) {
      app.loadNotices();
    }

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close notifications',
      barrierColor: AppColors.ink.withValues(alpha: 0.1),
      transitionDuration: AppMotion.sheet,
      pageBuilder: (_, _, _) => const Material(
        type: MaterialType.transparency,
        child: _NotificationMenu(),
      ),
      transitionBuilder: (context, animation, _, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.arriving,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _NotificationMenu extends StatelessWidget {
  const _NotificationMenu();

  Future<void> _markRead(BuildContext context, AppNotice notice) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<AppState>().markNoticeRead(notice);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final unread = [
      for (final n in app.notices)
        if (n.isUnread) n,
    ];
    final width = MediaQuery.sizeOf(context).width;

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppLayout.popoverTop,
          right: AppLayout.popoverMargin,
        ),
        child: SizedBox(
          width: width - AppLayout.popoverMargin * 2 < AppLayout.popoverMaxWidth
              ? width - AppLayout.popoverMargin * 2
              : AppLayout.popoverMaxWidth,
          child: BrutCard(
            shadow: AppShadows.lg,
            padding: const EdgeInsets.all(AppLayout.between),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const BrutIconTile(
                      icon: Icons.notifications_none,
                      size: 40,
                      tone: BrutTone.brand,
                    ),
                    const SizedBox(width: AppLayout.between),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            unread.isEmpty
                                ? 'Nothing new'
                                : '${unread.length} unread',
                            style: AppText.cardTitle.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          const MonoLabel('Tap one to mark it read'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppLayout.between),

                if (unread.isEmpty)
                  const BrutInlineMessage(
                    tone: BrutTone.neutral,
                    icon: Icons.check,
                    text: 'Everything here has been read.',
                  )
                else
                  // Four at most. This is a glance, and a window you have
                  // to scroll is a screen wearing a disguise.
                  for (final notice in unread.take(4)) ...[
                    _NoticeRow(
                      notice: notice,
                      onTap: () => _markRead(context, notice),
                    ),
                    const SizedBox(height: 8),
                  ],

                if (unread.length > 4) ...[
                  const SizedBox(height: 2),
                  MonoLabel('${unread.length - 4} more'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.notice, required this.onTap});

  final AppNotice notice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BrutSurface(
      onTap: onTap,
      radius: AppRadius.controlAll,
      shadow: AppShadows.sm,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            notice.title,
            style: AppText.body.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            notice.body,
            style: AppText.caption.copyWith(color: context.palette.subtle),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
