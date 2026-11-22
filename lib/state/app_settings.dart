import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferences that belong to this device rather than to the account.
///
/// There is no settings endpoint, so these do not follow you to another
/// phone — the Settings screen says so rather than implying otherwise.
/// They are kept here, outside `AppState`, because signing out must not
/// throw away the theme: a dark screen turning white on log out would
/// read as a bug.
///
/// Every read and write is wrapped: a device with blocked or full storage
/// still runs, it just forgets.
class AppSettings extends ChangeNotifier {
  static const _themeKey = 'settings.themeMode';
  static const _motionKey = 'settings.reduceMotion';
  static const _dashboardChartKey = 'settings.dashboardChart';

  ThemeMode _themeMode = ThemeMode.system;
  bool _reduceMotion = false;
  String? _dashboardChart;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;

  /// The title of the Analytics chart the dashboard shows, or null for
  /// the first one. A title rather than an index, so adding a chart does
  /// not move someone's choice onto a different one.
  String? get dashboardChart => _dashboardChart;

  /// Whether the dashboard's money figure is covered.
  ///
  /// Deliberately not persisted. Every launch starts covered, because
  /// the point of it is the person standing next to you — and a setting
  /// that remembers "shown" would be uncovered on the one occasion it
  /// mattered. Uncovering is a decision made in the moment and it lasts
  /// only as long as the app is open.
  bool get balanceHidden => _balanceHidden;
  bool _balanceHidden = true;

  void toggleBalanceHidden() {
    _balanceHidden = !_balanceHidden;
    notifyListeners();
  }

  /// Turns off the press animation, screen transitions and every other
  /// movement in the app. The OS-level setting is honoured too, so a
  /// phone already asking for reduced motion gets it without this.
  bool get reduceMotion => _reduceMotion;

  /// False until the stored values have been read. The app renders with
  /// the defaults meanwhile, which is one frame at most.
  bool get isLoaded => _loaded;

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_themeKey);
      _themeMode =
          ThemeMode.values.where((m) => m.name == stored).firstOrNull ??
          ThemeMode.system;
      _reduceMotion = prefs.getBool(_motionKey) ?? false;
      // The per-phone accent was removed. Clearing the key means a
      // phone that had chosen one goes back to its department's
      // colour instead of keeping a choice it can no longer change.
      await prefs.remove('settings.accent');
      _dashboardChart = prefs.getString(_dashboardChartKey);
    } catch (_) {
      // Storage is unavailable. The defaults are already correct.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _write((prefs) => prefs.setString(_themeKey, mode.name));
  }

  Future<void> setReduceMotion(bool value) async {
    if (value == _reduceMotion) return;
    _reduceMotion = value;
    notifyListeners();
    await _write((prefs) => prefs.setBool(_motionKey, value));
  }

  Future<void> setDashboardChart(String title) async {
    if (title == _dashboardChart) return;
    _dashboardChart = title;
    notifyListeners();
    await _write((prefs) => prefs.setString(_dashboardChartKey, title));
  }

  static const _tourKey = 'tour.seenBy';

  /// Bumped by Settings to ask the dashboard for its tour again.
  final tourRequests = ValueNotifier<int>(0);

  /// Whether this phone has shown [who] the first-sign-in tour. True when
  /// storage fails, so a phone that cannot remember is not walked through
  /// it on every launch.
  Future<bool> tourSeen(String who) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_tourKey)?.contains(who) ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<void> markTourSeen(String who) => _write((prefs) async {
    final seen = prefs.getStringList(_tourKey) ?? const <String>[];
    if (!seen.contains(who)) {
      await prefs.setStringList(_tourKey, [...seen, who]);
    }
  });

  @override
  void dispose() {
    tourRequests.dispose();
    super.dispose();
  }

  /// The choice is applied immediately and persisted afterwards, so a
  /// storage failure costs the memory of it, never the setting itself.
  Future<void> _write(Future<void> Function(SharedPreferences) body) async {
    try {
      await body(await SharedPreferences.getInstance());
    } catch (_) {
      // Nothing to recover: the value is already live in memory.
    }
  }
}

extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System',
  };

  String get explanation => switch (this) {
    ThemeMode.light => 'Always the light canvas.',
    ThemeMode.dark => 'Always the dark canvas.',
    ThemeMode.system => 'Follows your phone, and changes with it.',
  };
}
