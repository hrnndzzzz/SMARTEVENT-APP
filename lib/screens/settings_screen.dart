import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Device settings.
///
/// Nothing here is stored on the account yet — there is no settings
/// endpoint — so the screen says so rather than implying a preference
/// follows you to another device. Dark mode is disabled outright, because
/// the screens that have not been converted to the design system would
/// render dark text on a dark canvas.
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
                      text: 'These stay on this device. There is no settings '
                          'endpoint yet, so they do not follow your account.',
                    ),
                    const SizedBox(height: 18),
                    const _SwitchTile(
                      label: 'Dark mode',
                      subtitle: 'Not available yet — most screens would be '
                          'unreadable on a dark canvas.',
                      value: false,
                      onChanged: null,
                    ),
                    const SizedBox(height: 10),
                    _SwitchTile(
                      label: 'Biometric login',
                      subtitle: 'Unlock with your fingerprint or face instead '
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
