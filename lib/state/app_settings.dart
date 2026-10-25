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

  ThemeMode _themeMode = ThemeMode.system;
  bool _reduceMotion = false;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;

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
