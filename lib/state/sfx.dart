import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What just happened, as a sound.
///
/// Four, not forty. A sound per widget is how an interface ends up
/// chirping at people until they mute the phone; a sound per *outcome*
/// stays informative, because each one means something different.
enum Sfx {
  /// A control was pressed. Short and dry, meant to be felt more than
  /// heard.
  tap('tap.wav'),

  /// Something was saved, sent or accepted.
  confirm('confirm.wav'),

  /// Something was refused: a failed save, a validation error.
  refuse('refuse.wav'),

  /// Something arrived that was not asked for.
  notify('notify.wav');

  const Sfx(this.asset);

  final String asset;

  String get path => 'sfx/$asset';
}

/// Plays the interface sounds, and the haptics that go with them.
///
/// Sound and vibration are one setting rather than two. They answer the
/// same question — "did that register?" — and someone who turns one off
/// almost always wants the other off too. The phone's own silent switch
/// still wins on iOS; this is on top of it, not instead.
///
/// Every failure here is swallowed. An interface that cannot be used
/// because a click would not play is a worse interface than a silent
/// one.
class SfxPlayer extends ChangeNotifier {
  SfxPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer(playerId: 'smartevent-sfx');

  static const String _prefsKey = 'sfx_enabled';

  final AudioPlayer _player;

  bool _enabled = true;
  bool get enabled => _enabled;

  /// Reads the stored preference. Sound is on unless someone turned it
  /// off: an app that is silent until you find a setting is an app whose
  /// sound nobody knows about.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? true;
    } catch (_) {
      _enabled = true;
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    // A sound the moment it is switched on, so the control proves
    // itself rather than being taken on trust.
    if (value) play(Sfx.confirm);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // Applies for this run regardless.
    }
  }

  /// Plays [sound] and its haptic. Returns immediately; nothing waits on
  /// a click finishing.
  void play(Sfx sound) {
    if (!_enabled) return;
    _haptic(sound);
    unawaited(_playAsset(sound));
  }

  Future<void> _playAsset(Sfx sound) async {
    try {
      // Stop first: taps can come faster than a sound finishes, and
      // overlapping copies of the same click sound like a stutter.
      await _player.stop();
      await _player.play(
        AssetSource(sound.path),
        volume: sound == Sfx.tap ? 0.35 : 0.5,
      );
    } catch (_) {
      // No audio device, no asset, a platform that refuses: the button
      // still worked.
    }
  }

  static void _haptic(Sfx sound) {
    try {
      switch (sound) {
        case Sfx.tap:
          HapticFeedback.selectionClick();
        case Sfx.confirm:
          HapticFeedback.lightImpact();
        case Sfx.refuse:
          HapticFeedback.heavyImpact();
        case Sfx.notify:
          HapticFeedback.mediumImpact();
      }
    } catch (_) {
      // Desktop and the simulator have no vibration motor.
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }
}
