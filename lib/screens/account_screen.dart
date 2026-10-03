import 'about_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import 'welcome_screen.dart';
import 'settings_screen.dart';
import 'edit_profile_screen.dart';
import 'notification_prefs_screen.dart';
import 'help_screen.dart';
import 'admin_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

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

  static String _roleLabel(UserRole? role) => switch (role) {
    UserRole.officer => 'Officer (view only)',
    UserRole.treasurer => 'Treasurer',
    UserRole.adviser => 'Faculty Adviser',
    UserRole.sdsStaff => 'SDS Staff',
    UserRole.admin => 'Organization Administrator',
    UserRole.superAdmin => 'Super Administrator',
    null => 'Guest',
  };

  Future<void> _logout(BuildContext context) async {
    // Awaited so the stored token is gone before the welcome screen shows;
    // otherwise a fast relaunch could still find it and restore the
    // session we just signed out of.
    await context.read<AppState>().signOut();
    if (!context.mounted) return;
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
                    child: BrutIconButton(
                      icon: Icons.arrow_back,
                      label: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Column(
                              children: [
                                BrutSurface(
                                  fill: app.themeColor,
                                  radius: AppRadius.pill,
                                  width: 76,
                                  height: 76,
                                  alignment: Alignment.center,
                                  child: Text(
                                    initials,
                                    style: AppText.moneyLarge.copyWith(
                                      fontSize: 26,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  name,
                                  textAlign: TextAlign.center,
                                  style: AppText.titleBig,
                                ),
                                const SizedBox(height: 6),
                                MonoLabel(roleLabel),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          _MenuTile(
                            icon: Icons.person_outline,
                            label: 'Edit profile',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EditProfileScreen(
                                  name: name,
                                  role: roleLabel,
                                ),
                              ),
                            ),
                          ),
                          if (app.currentRole?.canManageMembers ?? false)
                            _MenuTile(
                              icon: Icons.manage_accounts_outlined,
                              label: 'Administration',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AdminScreen(),
                                ),
                              ),
                            ),
                          _MenuTile(
                            icon: Icons.settings_outlined,
                            label: 'Settings',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            ),
                          ),
                          _MenuTile(
                            icon: Icons.notifications_none,
                            label: 'Notification preferences',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const NotificationPrefsScreen(),
                              ),
                            ),
                          ),
                          _MenuTile(
                            icon: Icons.help_outline,
                            label: 'Help and support',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const HelpScreen(),
                              ),
                            ),
                          ),
                          _MenuTile(
                            icon: Icons.info_outline,
                            label: 'About',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AboutScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  BrutButton(
                    label: 'Log out',
                    icon: Icons.logout,
                    tone: BrutTone.coral,
                    onPressed: () => _logout(context),
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

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BrutListRow(
        title: label,
        onTap: onTap,
        marker: BrutIconTile(icon: icon, size: 32),
      ),
    );
  }
}
