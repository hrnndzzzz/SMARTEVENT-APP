import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/models/notification.dart';
import '../api/notification_service.dart';

/// Workmanager runs this in a background isolate, about every 15 minutes.
@pragma('vm:entry-point')
void phoneAlertsDispatcher() {
  Workmanager().executeTask((task, input) async {
    await PhoneAlerts.check();
    return true;
  });
}

/// The in-app notices, shown as phone notifications too.
///
/// There is no push service: the phone asks the server about every 15
/// minutes in the background, Android's shortest interval, which battery
/// saving can stretch. Every call is best effort, like [TokenStore]: a
/// missing plugin (tests, the demo) or an unreachable server only means no
/// notification this time.
class PhoneAlerts {
  const PhoneAlerts._();

  static const _task = 'notices';
  static const _shownKey = 'phone_alerts.shown';
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'notices',
      'Notices',
      channelDescription: 'New SMARTEVENT notices',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static Future<void> _init() => _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    ),
  );

  /// Signed in: ask once for permission (Android 13+) and start checking.
  static Future<void> start() async {
    try {
      await _init();
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await Workmanager().initialize(phoneAlertsDispatcher);
      await Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {
      // No notifications on this phone; the in-app list still has them.
    }
  }

  /// Signed out: stop checking, and let the next account start fresh.
  static Future<void> stop() async {
    try {
      await Workmanager().cancelByUniqueName(_task);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_shownKey);
    } catch (_) {
      // Nothing stored to sign in with either way, so a check finds nothing.
    }
  }

  /// One background check.
  static Future<void> check() async {
    try {
      await ApiConfig.load();
      // A sleeping free-tier server takes about a minute to wake.
      final client = ApiClient(timeout: const Duration(seconds: 60));
      // A sign-in not remembered on this phone left nothing to check with.
      if (await client.restoreToken() == null) return;
      final notices = await NotificationService(
        client,
      ).list(unreadOnly: true, limit: 20);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // the app may have signed out since
      final shown = prefs.getStringList(_shownKey);
      final fresh = freshNotices(notices, shown);
      if (fresh.isNotEmpty) await _init();
      for (final notice in fresh) {
        await _plugin.show(
          id: notice.id.hashCode,
          title: notice.title,
          body: notice.body,
          notificationDetails: _details,
        );
      }
      await prefs.setStringList(_shownKey, rememberShown(notices, shown));
    } catch (_) {
      // Unreachable or signed out elsewhere: try again next time.
    }
  }
}

/// The notices not on the phone yet. The first check after signing in
/// ([shown] null) only takes note, so older unread notices don't all
/// arrive at once.
List<AppNotice> freshNotices(List<AppNotice> notices, List<String>? shown) =>
    shown == null
    ? const []
    : [
        for (final notice in notices)
          if (!shown.contains(notice.id)) notice,
      ];

/// What has been shown, newest first, kept to the last 200.
List<String> rememberShown(List<AppNotice> notices, List<String>? shown) => {
  for (final notice in notices) notice.id,
  ...?shown,
}.take(200).toList();
