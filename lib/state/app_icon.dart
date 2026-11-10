import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which launcher icon the phone shows.
///
/// Android has no API for "change my icon". What it has is components:
/// the two `<activity-alias>` entries in AndroidManifest.xml, each
/// pointing at the same MainActivity with a different icon on it, one
/// enabled at a time. Switching is enabling one and disabling the
/// other, which is why this lives behind a method channel rather than
/// in Dart.
///
/// Two options because the logo was delivered on two grounds and
/// nothing here is invented artwork. A third in the brand's orange
/// would lose the arrow, which is orange itself.
enum AppIcon {
  navy,
  light;

  String get label => switch (this) {
    AppIcon.navy => 'Navy',
    AppIcon.light => 'White',
  };

  String get explanation => switch (this) {
    AppIcon.navy => 'The mark on its navy square.',
    AppIcon.light => 'The same mark on white.',
  };
}

/// Reads and writes the enabled launcher alias.
///
/// Every failure is swallowed into "navy" or a false: an icon is not
/// worth an error dialog, and the one platform that answers this is
/// Android. Everywhere else the app simply does not offer the choice.
class AppIcons {
  const AppIcons({this.channel = _default});

  /// Overridable so a test can answer without a platform behind it.
  final MethodChannel channel;

  static const MethodChannel _default = MethodChannel('smartevent/icon');

  /// Whether this build can change it at all.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Which one is showing now. The manifest's default reads as "not
  /// explicitly set" rather than as enabled, so an untouched install
  /// answers navy without anything having been written.
  Future<AppIcon> current() async {
    if (!isSupported) return AppIcon.navy;
    try {
      final name = await channel.invokeMethod<String>('current');
      return AppIcon.values.where((i) => i.name == name).firstOrNull ??
          AppIcon.navy;
    } catch (_) {
      return AppIcon.navy;
    }
  }

  /// True when the swap went through. Note that the launcher decides
  /// when to redraw: some show the new icon at once, some after a
  /// moment, some not until the home screen is next rebuilt. The
  /// screen says so rather than implying it is instant.
  Future<bool> set(AppIcon icon) async {
    if (!isSupported) return false;
    try {
      await channel.invokeMethod<void>('set', icon.name);
      return true;
    } catch (_) {
      return false;
    }
  }
}
