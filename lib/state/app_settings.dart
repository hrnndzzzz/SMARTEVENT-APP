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
  static const _navKey = 'settings.navStyle';
  static const _dockXKey = 'settings.dockX';
  static const _dockYKey = 'settings.dockY';

  ThemeMode _themeMode = ThemeMode.system;
  bool _reduceMotion = false;
  NavStyle _navStyle = NavStyle.floating;
  double _dockX = 1;
  double _dockY = 0.88;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;

  /// Turns off the press animation, screen transitions and every other
  /// movement in the app. The OS-level setting is honoured too, so a
  /// phone already asking for reduced motion gets it without this.
  bool get reduceMotion => _reduceMotion;

  /// How the quick actions are reached: a button you can move, a rail
  /// down the side, or a bar across the bottom. The same actions either
  /// way — only where your thumb finds them changes.
  NavStyle get navStyle => _navStyle;

  /// Where the floating button sits, as a fraction of the screen. It
  /// snaps to whichever side is nearer, so x is only ever 0 or 1; y is
  /// wherever it was left.
  double get dockX => _dockX;
  double get dockY => _dockY;

  /// False until the stored values have been read. The app renders with
  /// the defaults meanwhile, which is one frame at most.
  bool get isLoaded => _loaded;

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_themeKey);
      _themeMode = ThemeMode.values
              .where((m) => m.name == stored)
              .firstOrNull ??
          ThemeMode.system;
      _reduceMotion = prefs.getBool(_motionKey) ?? false;
      final nav = prefs.getString(_navKey);
      _navStyle = NavStyle.values
              .where((n) => n.name == nav)
              .firstOrNull ??
          NavStyle.floating;
      _dockX = prefs.getDouble(_dockXKey) ?? 1;
      _dockY = prefs.getDouble(_dockYKey) ?? 0.88;
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

  Future<void> setNavStyle(NavStyle style) async {
    if (style == _navStyle) return;
    _navStyle = style;
    notifyListeners();
    await _write((prefs) => prefs.setString(_navKey, style.name));
  }

  /// Called when the button is dropped. [x] is snapped to a side by the
  /// caller; [y] is clamped so it cannot be parked under the status bar
  /// or behind the home indicator.
  Future<void> setDockPosition(double x, double y) async {
    final nx = x >= 0.5 ? 1.0 : 0.0;
    final ny = y.clamp(0.06, 0.92);
    if (nx == _dockX && ny == _dockY) return;
    _dockX = nx;
    _dockY = ny;
    notifyListeners();
    await _write((prefs) async {
      await prefs.setDouble(_dockXKey, nx);
      await prefs.setDouble(_dockYKey, ny);
    });
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

/// Where the quick actions live.
enum NavStyle { floating, rail, bar }

extension NavStyleInfo on NavStyle {
  String get label => switch (this) {
    NavStyle.floating => 'Floating button',
    NavStyle.rail => 'Side rail',
    NavStyle.bar => 'Bottom bar',
  };

  String get blurb => switch (this) {
    NavStyle.floating => 'A button you can drag anywhere. It stays where '
        'you leave it.',
    NavStyle.rail => 'A column down the side, always showing the areas.',
    NavStyle.bar => 'A row across the bottom, within reach of your thumb.',
  };

  IconData get icon => switch (this) {
    NavStyle.floating => Icons.radio_button_checked,
    NavStyle.rail => Icons.view_sidebar_outlined,
    NavStyle.bar => Icons.table_rows_outlined,
  };
}
