import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/notice_shelf.dart';
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
/// nothing, so when the inbox has not been fetched yet it fetches rather
/// than showing fewer than the badge promised.
abstract final class NotificationMenu {
  static Future<void> show(BuildContext context) {
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

/// How a notice looks, by what produced it.
///
/// The backend names two kinds today. Anything it adds later gets the
/// neutral treatment rather than no treatment, so a new kind appears as
/// a plain notice instead of disappearing.
({IconData icon, BrutTone tone, String tag}) _styleOf(AppNotice notice) {
  return switch (notice.kind) {
    'sap_workflow' => (
      icon: Icons.description_outlined,
      tone: BrutTone.brand,
      tag: 'Form',
    ),
    'registration_confirmation' => (
      icon: Icons.person_add_alt,
      tone: BrutTone.mint,
      tag: 'Account',
    ),
    _ => (icon: Icons.info_outline, tone: BrutTone.neutral, tag: 'Notice'),
  };
}

/// When it arrived, short enough for the corner of a row.
String _when(DateTime at) {
  final gap = DateTime.now().difference(at);
  if (gap.inMinutes < 1) return 'Now';
  if (gap.inMinutes < 60) return '${gap.inMinutes}m';
  if (gap.inHours < 24) return '${gap.inHours}h';
  if (gap.inDays < 7) return '${gap.inDays}d';
  return '${at.day}/${at.month}';
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

  Future<void> _markAllRead(BuildContext context, List<AppNotice> rows) async {
    final app = context.read<AppState>();
    for (final notice in rows) {
      if (notice.isUnread) await app.markNoticeRead(notice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shelf = context.watch<NoticeShelf>();

    // Swiped-away notices stay gone, so the list is what the server sent
    // minus what this phone has put aside.
    final rows = [
      for (final n in app.notices)
        if (!shelf.isDismissed(n.id)) n,
    ];
    final unread = rows.where((n) => n.isUnread).length;

    final size = MediaQuery.sizeOf(context);
    final width =
        size.width - AppLayout.popoverMargin * 2 < AppLayout.popoverMaxWidth
        ? size.width - AppLayout.popoverMargin * 2
        : AppLayout.popoverMaxWidth;

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppLayout.popoverTop,
          right: AppLayout.popoverMargin,
        ),
        child: SizedBox(
          width: width,
          child: BrutCard(
            shadow: AppShadows.lg,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Notifications',
                        style: AppText.cardTitle.copyWith(fontSize: 15),
                      ),
                    ),
                    _TextAction(
                      label: 'Mark read',
                      onTap: unread == 0
                          ? null
                          : () => _markAllRead(context, rows),
                    ),
                    const SizedBox(width: 10),
                    _ClearAll(
                      enabled: rows.isNotEmpty,
                      onTap: () => shelf.dismissAll(rows.map((n) => n.id)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (rows.isEmpty)
                  const _CaughtUp()
                else
                  // Past a little over half the screen it scrolls, so the
                  // window never grows into a page.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: size.height * 0.56),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            _SwipeToDismiss(
                              key: ValueKey(rows[i].id),
                              onDismissed: () => shelf.dismiss(rows[i].id),
                              child: _NoticeRow(
                                notice: rows[i],
                                onTap: () => _markRead(context, rows[i]),
                              ),
                            ),
                            if (i != rows.length - 1)
                              const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  ),

                if (rows.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'SWIPE A NOTIFICATION SIDEWAYS TO REMOVE IT',
                      style: AppText.monoLabel.copyWith(fontSize: 9),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An underlined text link, greyed out when there is nothing to do.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final live = onTap != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        label,
        style: AppText.caption.copyWith(
          decoration: TextDecoration.underline,
          color: live ? context.palette.ink : context.palette.muted,
        ),
      ),
    );
  }
}

class _ClearAll extends StatelessWidget {
  const _ClearAll({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BrutButton(
      label: 'Clear all',
      tone: BrutTone.coral,
      size: BrutSize.small,
      expand: false,
      onPressed: enabled ? onTap : null,
    );
  }
}

class _CaughtUp extends StatelessWidget {
  const _CaughtUp();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardAll,
        border: Border.all(
          color: context.palette.line,
          width: 2,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Center(
        child: Text(
          'You\'re all caught up.',
          style: AppText.caption.copyWith(color: context.palette.subtle),
        ),
      ),
    );
  }
}

/// A row that follows your finger sideways and leaves if you mean it.
///
/// Past 90 logical pixels it goes; short of that it springs back. A
/// swipe never counts as a tap, and the vertical drag still belongs to
/// the list so the panel can scroll.
class _SwipeToDismiss extends StatefulWidget {
  const _SwipeToDismiss({
    super.key,
    required this.child,
    required this.onDismissed,
  });

  final Widget child;
  final VoidCallback onDismissed;

  @override
  State<_SwipeToDismiss> createState() => _SwipeToDismissState();
}

class _SwipeToDismissState extends State<_SwipeToDismiss> {
  static const double _threshold = 90;

  double _offset = 0;
  bool _leaving = false;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final width = MediaQuery.sizeOf(context).width;

    return GestureDetector(
      // Horizontal only: dragging up and down has to keep scrolling the
      // list underneath.
      onHorizontalDragUpdate: (d) =>
          setState(() => _offset += d.delta.dx),
      onHorizontalDragEnd: (_) {
        if (_offset.abs() >= _threshold) {
          setState(() {
            _leaving = true;
            _offset = _offset.isNegative ? -width : width;
          });
          // Let it travel before it is taken out of the list.
          Future.delayed(
            still ? Duration.zero : AppMotion.enter,
            widget.onDismissed,
          );
        } else {
          setState(() => _offset = 0);
        }
      },
      child: AnimatedContainer(
        duration: _offset == 0 || _leaving
            ? (still ? Duration.zero : AppMotion.enter)
            : Duration.zero,
        curve: _leaving ? AppMotion.leaving : AppMotion.arriving,
        transform: Matrix4.translationValues(_offset, 0, 0),
        child: Opacity(
          // Fades as it goes, so the row looks like it is leaving rather
          // than sliding behind something.
          opacity: (1 - (_offset.abs() / (_threshold * 2))).clamp(0.0, 1.0),
          child: widget.child,
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
    final style = _styleOf(notice);
    final palette = context.palette;

    return Semantics(
      button: true,
      label: '${notice.title}. Swipe to dismiss',
      child: BrutSurface(
        onTap: onTap,
        // Unread carries a light fill; read rows sit flat, so the ones
        // that still want you are the ones that stand out.
        fill: notice.isUnread ? palette.canvas : palette.surface,
        radius: AppRadius.controlAll,
        shadow: AppShadows.sm,
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrutIconTile(icon: style.icon, tone: style.tone, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          notice.title,
                          style: AppText.body.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (notice.isUnread) ...[
                        const SizedBox(width: 6),
                        Semantics(
                          label: 'unread',
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppColors.coral,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notice.body,
                    style: AppText.caption.copyWith(
                      fontSize: 12,
                      color: palette.subtle,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _when(notice.createdAt),
              style: AppText.monoLabel.copyWith(fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}
