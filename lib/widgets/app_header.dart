import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import 'account_menu.dart';
import 'connection_banner.dart';
import 'notification_peek.dart';

/// The top bar on every section screen: the brand pill, who you are signed
/// in as, the bell, and the avatar.
///
/// The department accent is used as a *fill* here, never as text. The
/// palette is light enough for ink on top of it and far too light to read
/// against the canvas, which is why the wordmark lives inside a pill
/// rather than being coloured directly.
class AppHeader extends StatelessWidget {
  /// Kept for callers that still pass it; the header no longer draws it.
  /// The dashboard says who you are under the greeting, where there is
  /// room for it, and the account menu says it in full.
  final String? subtitle;
  final VoidCallback? onBellTap;

  /// Overrides what the avatar does. It opens the account menu by
  /// default, which is what every screen wanted.
  final VoidCallback? onAvatarTap;

  /// Shown when this screen was pushed rather than swiped to. Screens
  /// that used to be tabs did not need one; the same screens opened from
  /// the menu very much do.
  final VoidCallback? onBack;

  const AppHeader({
    super.key,
    this.subtitle,
    this.onBellTap,
    this.onAvatarTap,
    this.onBack,
  });

  static String _initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  /// `CITE · TREASURER`. Falls back to whichever half is known rather than
  /// printing a placeholder for the other.
  static String? scopeLineFor(AppState app) {
    final role = app.currentRole?.label;
    final department = app.currentAccount?.departmentId == null
        ? null
        : app.themeDepartment.label;
    final parts = [department, role].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // The department accent comes from the theme rather than from state:
    // main.dart puts it there, so every identity surface reads one value.
    final accent = Theme.of(context).colorScheme.secondary;
    final initials = _initialsFor(app.currentAccount?.name ?? 'Guest');

    return Row(
      children: [
        if (onBack != null) ...[
          BrutIconButton(
            icon: Icons.arrow_back,
            label: 'Back',
            onPressed: onBack,
          ),
          const SizedBox(width: 10),
        ],
        // One row, three things, all on the same baseline. The role used
        // to sit under the wordmark, which pushed the pill half a line
        // above the two buttons it is supposed to line up with.
        BrutSurface(
          fill: accent,
          radius: AppRadius.pill,
          shadow: AppShadows.sm,
          padding: const EdgeInsets.fromLTRB(10, 5, 14, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 15, color: AppColors.ink),
              const SizedBox(width: 5),
              Text('SmartEvent', style: AppText.wordmark),
            ],
          ),
        ),
        const Spacer(),
        _BellWithBadge(onTap: onBellTap),
        const SizedBox(width: 8),
        _Avatar(
          initials: initials,
          accent: accent,
          onTap: onAvatarTap ?? () => AccountMenu.show(context),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initials,
    required this.accent,
    required this.onTap,
  });

  final String initials;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        BrutSurface(
          onTap: onTap,
          semanticLabel: 'Account',
          fill: accent,
          radius: AppRadius.pill,
          shadow: AppShadows.sm,
          width: 38,
          height: 38,
          alignment: Alignment.center,
          child: Text(initials, style: AppText.number.copyWith(fontSize: 13)),
        ),
        // Whether the backend is answering, where you are already looking.
        Positioned(
          right: -2,
          bottom: -2,
          child: ConnectionDot(ringColor: context.palette.canvas),
        ),
      ],
    );
  }
}

/// The bell, with an unread count when there is one.
///
/// The number comes from `/notifications/unread-count` via AppState rather
/// than from counting a loaded list, so it is right even before the inbox
/// has been opened. No badge at all when the count is zero — a "0" is
/// noise.
class _BellWithBadge extends StatelessWidget {
  const _BellWithBadge({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final count = context.watch<AppState>().unreadNoticeCount;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // A tap opens the inbox; a hold shows what the number counts.
        NotificationPeek(
          onTap: onTap,
          child: BrutIconButton(
            icon: Icons.notifications_none,
            label: count > 0 ? 'Notifications, $count unread' : 'Notifications',
            onPressed: onTap,
            size: 38,
          ),
        ),
        if (count > 0)
          Positioned(
            right: -5,
            top: -5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: AppColors.coral,
                borderRadius: AppRadius.pill,
                border: context.borderAll,
              ),
              child: Text(
                // Past 99 the exact number stops being useful and starts
                // breaking the layout.
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: AppText.monoLabel.copyWith(
                  fontSize: 9,
                  color: context.palette.ink,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
