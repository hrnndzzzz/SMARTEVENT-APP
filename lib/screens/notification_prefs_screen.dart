import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Which notifications you want.
///
/// Like Settings, these are device-local: the backend raises notifications
/// but has no endpoint for preferences, so turning one off here does not
/// stop it being raised. The screen says so rather than implying it does.
class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  bool _lowStock = true;
  bool _approvals = true;
  bool _eventReminders = true;
  bool _financialLogs = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BrutHeader(
              eyebrow: 'Account',
              title: 'Notification preferences',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Choose what you want to be notified about.',
                      style: AppText.caption,
                    ),
                    const SizedBox(height: 14),
                    const BrutInlineMessage(
                      tone: BrutTone.sun,
                      icon: Icons.info_outline,
                      text: 'These stay on this device. The backend has no '
                          'preference endpoint yet, so notifications are '
                          'still recorded in your inbox either way.',
                    ),
                    const SizedBox(height: 18),
                    _PrefTile(
                      label: 'Low-stock alerts',
                      subtitle:
                          'When inventory items fall below their threshold.',
                      value: _lowStock,
                      onChanged: (v) => setState(() => _lowStock = v),
                    ),
                    const SizedBox(height: 10),
                    _PrefTile(
                      label: 'Pending approvals',
                      subtitle: 'When a request needs your review.',
                      value: _approvals,
                      onChanged: (v) => setState(() => _approvals = v),
                    ),
                    const SizedBox(height: 10),
                    _PrefTile(
                      label: 'Event reminders',
                      subtitle: 'Upcoming and overdue event activity.',
                      value: _eventReminders,
                      onChanged: (v) => setState(() => _eventReminders = v),
                    ),
                    const SizedBox(height: 10),
                    _PrefTile(
                      label: 'Financial logs',
                      subtitle: 'New expenses and transactions recorded.',
                      value: _financialLogs,
                      onChanged: (v) => setState(() => _financialLogs = v),
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

class _PrefTile extends StatelessWidget {
  const _PrefTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      radius: AppRadius.rowAll,
      shadow: AppShadows.sm,
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
