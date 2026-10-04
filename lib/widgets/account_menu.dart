import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/about_screen.dart';
import '../screens/admin_screen.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/help_screen.dart';
import '../screens/notification_prefs_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/welcome_screen.dart';
import '../state/app_state.dart';
import '../state/reachability.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'connection_banner.dart';

/// The menu behind the avatar.
///
/// A popover rather than a screen: everything in it is one tap away from
/// where you already are, and none of it is a place you stay. It hangs
/// under the top bar on the right, over a light scrim, and the back
/// gesture closes it before it leaves the screen underneath.
abstract final class AccountMenu {
  static Future<void> show(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close the account menu',
      // Light: the screen underneath is still the subject, the menu is
      // just in front of it.
      barrierColor: AppColors.ink.withValues(alpha: 0.1),
      transitionDuration: AppMotion.sheet,
      // A route's page is not under the app's Material by default, and
      // text outside one renders with Flutter's missing-ancestor
      // underline. Transparent, so the scrim still shows through.
      pageBuilder: (_, _, _) => const Material(
        type: MaterialType.transparency,
        child: _AccountMenu(),
      ),
      transitionBuilder: (context, animation, _, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
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

class _AccountMenu extends StatelessWidget {
  const _AccountMenu();

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

  Future<void> _go(BuildContext context, Widget screen) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    await navigator.push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _logOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    // Awaited so the stored token is gone before the welcome screen shows;
    // otherwise a fast relaunch could still find it and restore the
    // session we just signed out of.
    await context.read<AppState>().signOut();
    if (!context.mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final name = app.currentAccount?.name ?? 'Guest';
    final accent = Theme.of(context).colorScheme.secondary;
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
                    BrutSurface(
                      fill: accent,
                      radius: AppRadius.pill,
                      shadow: AppShadows.sm,
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      child: Text(
                        _initialsFor(name),
                        style: AppText.moneyLarge.copyWith(fontSize: 17),
                      ),
                    ),
                    const SizedBox(width: AppLayout.between),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: AppText.cardTitle.copyWith(fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          MonoLabel(_roleLabel(app.currentRole)),
                          if (app.currentAccount?.email.isNotEmpty == true) ...[
                            const SizedBox(height: 2),
                            Text(
                              app.currentAccount!.email,
                              style: AppText.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppLayout.between),
                const _StatusRow(),
                const SizedBox(height: 10),
                _MenuRow(
                  icon: Icons.person_outline,
                  title: 'Edit profile',
                  hint: 'Your name and email on this device',
                  onTap: () => _go(
                    context,
                    EditProfileScreen(
                      name: name,
                      role: _roleLabel(app.currentRole),
                    ),
                  ),
                ),
                if (app.currentRole?.canManageMembers ?? false) ...[
                  const SizedBox(height: 6),
                  _MenuRow(
                    icon: Icons.manage_accounts_outlined,
                    title: 'Administration',
                    hint: 'Roster, accounts and the audit log',
                    onTap: () => _go(context, const AdminScreen()),
                  ),
                ],
                const SizedBox(height: 6),
                _MenuRow(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  hint: 'Theme and motion on this device',
                  onTap: () => _go(context, const SettingsScreen()),
                ),
                const SizedBox(height: 6),
                _MenuRow(
                  icon: Icons.notifications_none,
                  title: 'Notification preferences',
                  hint: 'What you want to be told about',
                  onTap: () => _go(context, const NotificationPrefsScreen()),
                ),
                const SizedBox(height: 6),
                _MenuRow(
                  icon: Icons.help_outline,
                  title: 'Help and support',
                  hint: 'How the app actually works',
                  onTap: () => _go(context, const HelpScreen()),
                ),
                const SizedBox(height: 6),
                _MenuRow(
                  icon: Icons.info_outline,
                  title: 'About SmartEvent',
                  hint: 'Version, modules and credits',
                  onTap: () => _go(context, const AboutScreen()),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: AppLayout.smallAction,
                  child: BrutButton(
                    label: 'Log out',
                    icon: Icons.logout,
                    tone: BrutTone.coral,
                    size: BrutSize.small,
                    onPressed: () => _logOut(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether the backend is answering, one line, where you would look for
/// it when something is not saving.
class _StatusRow extends StatelessWidget {
  const _StatusRow();

  @override
  Widget build(BuildContext context) {
    final state = context.reachable ?? Reachable.online;
    final label = switch (state) {
      Reachable.online => 'Online',
      Reachable.offline => 'No connection',
      Reachable.reconnecting => 'Reconnecting',
    };
    final detail = switch (state) {
      Reachable.online => 'The server is answering',
      Reachable.offline => 'Changes will not save',
      Reachable.reconnecting => 'Trying the server again',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        borderRadius: AppRadius.controlAll,
        border: context.borderAll,
      ),
      child: Row(
        children: [
          const ConnectionDot(size: 10),
          const SizedBox(width: AppLayout.tight),
          Text(
            label,
            style: AppText.body.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '· $detail',
              style: AppText.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BrutSurface(
      onTap: onTap,
      radius: AppRadius.rowAll,
      shadow: AppShadows.sm,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppText.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(hint, style: AppText.caption.copyWith(fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }
}
