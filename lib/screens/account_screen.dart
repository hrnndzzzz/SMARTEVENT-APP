import 'about_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'welcome_screen.dart';
import 'settings_screen.dart';
import 'edit_profile_screen.dart';
import 'notification_prefs_screen.dart';
import 'help_screen.dart';
import 'register_user_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  static String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static String _roleLabel(UserRole? role) => switch (role) {
    UserRole.officer => 'CITE Dept Officer',
    UserRole.adviser => 'Faculty Adviser',
    UserRole.admin => 'System Administrator',
    null => 'Guest',
  };

  void _logout(BuildContext context) {
    context.read<AppState>().signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        final name = app.currentAccount?.name ?? 'Guest';
        final roleLabel = _roleLabel(app.currentRole);
        final initials = _initialsFor(name);

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 34,
                                  backgroundColor: app.themeColor,
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: AppText.bodyFamily,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  name,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: AppText.headerFamily,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 18,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(roleLabel, style: AppText.caption),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          _MenuTile(
                            icon: Icons.person_outline,
                            label: 'Edit Profile',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EditProfileScreen(name: name, role: roleLabel),
                              ),
                            ),
                          ),
                          if (app.currentRole == UserRole.admin)
                            _MenuTile(
                              icon: Icons.person_add_alt_1_outlined,
                              label: 'Register User',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const RegisterUserScreen()),
                              ),
                            ),
                          _MenuTile(
                            icon: Icons.settings_outlined,
                            label: 'Settings',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            ),
                          ),
                          _MenuTile(
                            icon: Icons.notifications_none,
                            label: 'Notification Preferences',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const NotificationPrefsScreen()),
                            ),
                          ),
                          _MenuTile(
                            icon: Icons.help_outline,
                            label: 'Help & Support',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const HelpScreen()),
                            ),
                          ),
                          _MenuTile(
                            icon: Icons.info_outline,
                            label: 'About',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AboutScreen()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _MenuTile(
                    icon: Icons.logout,
                    label: 'Log Out',
                    iconColor: AppColors.brick,
                    labelColor: AppColors.brick,
                    onTap: () => _logout(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;
  final Color labelColor;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = AppColors.ink,
    this.labelColor = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppText.bodyFamily,
                fontSize: 14,
                color: labelColor,
              ),
            ),
            const Spacer(),
            if (labelColor == AppColors.ink)
              const Icon(Icons.chevron_right, size: 18, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}