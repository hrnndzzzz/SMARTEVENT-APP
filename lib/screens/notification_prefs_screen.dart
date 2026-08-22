import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() => _NotificationPrefsScreenState();
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Notification Preferences',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 19,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text('Choose what you want to be notified about.', style: AppText.caption),
              const SizedBox(height: 18),
              _prefTile('Low-stock alerts', 'When inventory items fall below threshold.', _lowStock, (v) => setState(() => _lowStock = v)),
              _prefTile('Pending approvals', 'When a request needs your review.', _approvals, (v) => setState(() => _approvals = v)),
              _prefTile('Event reminders', 'Upcoming and overdue event activity.', _eventReminders, (v) => setState(() => _eventReminders = v)),
              _prefTile('Financial logs', 'New expenses and transactions recorded.', _financialLogs, (v) => setState(() => _financialLogs = v)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _prefTile(String label, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.body.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.indigo),
        ],
      ),
    );
  }
}