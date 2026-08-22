import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class AppHeader extends StatelessWidget {
  final String initials;
  final String? subtitle;
  final Color subtitleBg;
  final Color subtitleColor;
  final VoidCallback onAvatarTap;
  final VoidCallback? onBellTap;

  const AppHeader({
    super.key,
    required this.initials,
    required this.onAvatarTap,
    this.subtitle,
    this.subtitleBg = AppColors.marigoldTint,
    this.subtitleColor = AppColors.marigoldText,
    this.onBellTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.indigo,
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
              const Text('SmartEvent', style: AppText.wordmark),
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
          icon: const Icon(Icons.notifications_none, color: AppColors.indigo, size: 22),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}