import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart' show Department;

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
  static const _accentKey = 'settings.accent';

  ThemeMode _themeMode = ThemeMode.system;
  bool _reduceMotion = false;
  Department? _accent;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;

  /// A colour chosen on this phone, or null to keep the one that comes
  /// with the account's department.
  ///
  /// The palette is the departments' own rather than a free colour
  /// wheel. Every one of these was picked to work as a fill with ink on
  /// top, in both themes, and none of them is coral — coral means "a
  /// problem", and a whole app wearing it would read as one. A picker
  /// that let someone choose otherwise would be offering a way to make
  /// the app unreadable.
  Department? get accent => _accent;

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
      final accent = prefs.getString(_accentKey);
      _accent = Department.values.where((d) => d.name == accent).firstOrNull;
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

  /// Null puts it back to the department's own colour.
  Future<void> setAccent(Department? value) async {
    if (value == _accent) return;
    _accent = value;
    notifyListeners();
    await _write(
      (prefs) => value == null
          // Removed rather than stored as a sentinel, so "never chose"
          // and "chose to go back" are the same state on the next
          // launch — which they are.
          ? prefs.remove(_accentKey)
          : prefs.setString(_accentKey, value.name),
    );
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
