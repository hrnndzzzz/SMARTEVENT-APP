import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class AppHeader extends StatelessWidget {
  final String? subtitle;
  final Color subtitleBg;
  final Color subtitleColor;
  final VoidCallback onAvatarTap;
  final VoidCallback? onBellTap;

  const AppHeader({
    super.key,
    required this.onAvatarTap,
    this.subtitle,
    this.subtitleBg = AppColors.marigoldTint,
    this.subtitleColor = AppColors.marigoldText,
    this.onBellTap,
  });

  static String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final themeColor = app.themeColor;
    final initials = _initialsFor(app.currentAccount?.name ?? 'Guest');

    return Row(
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: CircleAvatar(
            radius: 17,
            backgroundColor: themeColor,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFamily: AppText.bodyFamily,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SmartEvent', style: AppText.wordmark.copyWith(color: themeColor)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: subtitleBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontFamily: AppText.bodyFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                      color: subtitleColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        _BellWithBadge(color: themeColor, onTap: onBellTap),
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
  const _BellWithBadge({required this.color, required this.onTap});

  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final count = context.watch<AppState>().unreadNoticeCount;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(Icons.notifications_none, color: color, size: 22),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        if (count > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: AppColors.brick,
                borderRadius: BorderRadius.circular(20),
                // A ring so the badge stays legible over any header colour.
                border: Border.all(color: AppColors.background, width: 1.5),
              ),
              child: Text(
                // Past 99 the exact number stops being useful and starts
                // breaking the layout.
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
            ),
          ),
      ],
    );
  }
}