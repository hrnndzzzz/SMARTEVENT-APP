import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the picture is made of.
enum AvatarStyle {
  initials('initials', 'Initials'),
  pattern('pattern', 'Pattern'),
  photo('photo', 'Photo');

  const AvatarStyle(this.wireName, this.label);

  final String wireName;
  final String label;

  static AvatarStyle fromWire(String? value) => AvatarStyle.values.firstWhere(
    (s) => s.wireName == value,
    orElse: () => AvatarStyle.initials,
  );
}

/// The eight patterns, each drawn from the name rather than picked.
///
/// Two people with the same style and colour still get different marks,
/// and the mark follows a name change, so it never ends up describing
/// somebody who is no longer there.
enum AvatarPattern {
  blocks('blocks', 'Blocks'),
  dots('dots', 'Dots'),
  stripes('stripes', 'Stripes'),
  waves('waves', 'Waves'),
  triangles('triangles', 'Triangles'),
  rings('rings', 'Rings'),
  checks('checks', 'Checks'),
  sparkles('sparkles', 'Sparkles');

  const AvatarPattern(this.wireName, this.label);

  final String wireName;
  final String label;

  static AvatarPattern fromWire(String? value) =>
      AvatarPattern.values.firstWhere(
        (p) => p.wireName == value,
        orElse: () => AvatarPattern.blocks,
      );
}

/// The eight grounds a picture can sit on.
///
/// Bright enough to tell apart at 38 pixels in a header, and all light
/// enough to carry dark initials — the ink on an avatar does not follow
/// the theme, so the picture looks the same in both.
const List<int> avatarColors = [
  0xFFFFD93D, // yellow
  0xFF6BCB77, // green
  0xFF4D96FF, // blue
  0xFFFF5964, // coral
  0xFFB794F6, // lavender
  0xFFFF9F43, // orange
  0xFF5CE1E6, // aqua
  0xFFF2F1EC, // cream
];

/// A stable number from a name, for choosing a colour or a pattern
/// before anybody has chosen one.
int avatarSeed(String name) {
  var hash = 7;
  for (final unit in name.trim().toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}

/// How someone's picture is put together, and where it is kept.
///
/// On this device only. There is no avatar route on the backend, so a
/// picture does not follow an account to another phone — the screen says
/// so rather than implying a sync that is not there.
class Avatar extends ChangeNotifier {
  static const _styleKey = 'avatar.style';
  static const _colorKey = 'avatar.color';
  static const _patternKey = 'avatar.pattern';
  static const _photoKey = 'avatar.photo';

  AvatarStyle _style = AvatarStyle.initials;
  int? _color;
  AvatarPattern? _pattern;
  Uint8List? _photo;

  AvatarStyle get style => _style;
  Uint8List? get photo => _photo;

  /// The chosen colour, or the one this name would be given.
  int colorFor(String name) =>
      _color ?? avatarColors[avatarSeed(name) % avatarColors.length];

  /// The chosen pattern, or the one this name would be given.
  AvatarPattern patternFor(String name) =>
      _pattern ??
      AvatarPattern.values[(avatarSeed(name) ~/ 8) %
          AvatarPattern.values.length];

  bool get hasPhoto => _photo != null;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _style = AvatarStyle.fromWire(prefs.getString(_styleKey));
      _color = prefs.getInt(_colorKey);
      final pattern = prefs.getString(_patternKey);
      _pattern = pattern == null ? null : AvatarPattern.fromWire(pattern);
      final photo = prefs.getString(_photoKey);
      _photo = photo == null ? null : base64Decode(photo);
      // A photo that was removed outside this screen must not leave the
      // style pointing at nothing.
      if (_style == AvatarStyle.photo && _photo == null) {
        _style = AvatarStyle.initials;
      }
      notifyListeners();
    } catch (_) {
      // No stored picture is a perfectly good starting state.
    }
  }

  Future<void> save({
    required AvatarStyle style,
    required int color,
    required AvatarPattern pattern,
    required Uint8List? photo,
  }) async {
    _style = style;
    _color = color;
    _pattern = pattern;
    _photo = photo;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_styleKey, style.wireName);
      await prefs.setInt(_colorKey, color);
      await prefs.setString(_patternKey, pattern.wireName);
      if (photo == null) {
        await prefs.remove(_photoKey);
      } else {
        await prefs.setString(_photoKey, base64Encode(photo));
      }
    } catch (_) {
      // It stays for this run even if the device refuses to keep it.
    }
  }

  /// Signing out takes the picture with it: the next account on this
  /// phone must not inherit the last one's face.
  Future<void> clear() async {
    _style = AvatarStyle.initials;
    _color = null;
    _pattern = null;
    _photo = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_styleKey);
      await prefs.remove(_colorKey);
      await prefs.remove(_patternKey);
      await prefs.remove(_photoKey);
    } catch (_) {
      // Already gone from memory, which is what matters here.
    }
  }

  /// Two letters, or one, or a question mark — never an empty circle.
  static String initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }
}
