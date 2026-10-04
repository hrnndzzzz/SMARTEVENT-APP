import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_settings.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Device settings.
///
/// Nothing here is stored on the account — there is no settings endpoint
/// — so the screen says so rather than implying a preference follows you
/// to another device. The theme and reduce-motion choices do persist on
/// this phone and survive signing out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricLogin = false;
  bool _dataSaver = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BrutHeader(
              title: 'Settings',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BrutInlineMessage(
                      tone: BrutTone.sun,
                      icon: Icons.info_outline,
                      text:
                          'These stay on this device. There is no settings '
                          'endpoint yet, so they do not follow your account.',
                    ),
                    const SizedBox(height: 20),
                    const BrutSectionTitle('Appearance'),
                    const SizedBox(height: 10),
                    const _ThemePicker(),
                    const SizedBox(height: 18),
                    _SwitchTile(
                      label: 'Reduce motion',
                      subtitle:
                          'Turns off the press effect, screen '
                          'transitions and every other movement. Your '
                          'phone\'s own setting is honoured either way.',
                      value: settings.reduceMotion,
                      onChanged: settings.setReduceMotion,
                    ),
                    const SizedBox(height: 20),
                    const BrutSectionTitle('This device'),
                    const SizedBox(height: 10),
                    _SwitchTile(
                      label: 'Biometric login',
                      subtitle:
                          'Unlock with your fingerprint or face instead '
                          'of your password.',
                      value: _biometricLogin,
                      onChanged: (v) => setState(() => _biometricLogin = v),
                    ),
                    const SizedBox(height: 10),
                    _SwitchTile(
                      label: 'Data saver',
                      subtitle: 'Load receipt images at a lower resolution.',
                      value: _dataSaver,
                      onChanged: (v) => setState(() => _dataSaver = v),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;

    return BrutCard(
      radius: AppRadius.rowAll,
      shadow: enabled ? AppShadows.sm : AppShadows.none,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Light, Dark or System, as three choices you can see at once rather
/// than a switch that only says one of them.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final mode in ThemeMode.values) ...[
              Expanded(
                child: BrutSurface(
                  onTap: () => settings.setThemeMode(mode),
                  semanticLabel: mode.label,
                  fill: settings.themeMode == mode
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  radius: AppRadius.controlAll,
                  shadow: settings.themeMode == mode
                      ? AppShadows.base
                      : AppShadows.none,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Icon(switch (mode) {
                        ThemeMode.light => Icons.light_mode_outlined,
                        ThemeMode.dark => Icons.dark_mode_outlined,
                        ThemeMode.system => Icons.brightness_auto_outlined,
                      }, size: 20),
                      const SizedBox(height: 6),
                      Text(
                        mode.label,
                        style: AppText.buttonLabel.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              if (mode != ThemeMode.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(settings.themeMode.explanation, style: AppText.caption),
      ],
    );
  }
}
