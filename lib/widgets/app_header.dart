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
        IconButton(
          onPressed: onBellTap,
          icon: Icon(Icons.notifications_none, color: themeColor, size: 22),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}