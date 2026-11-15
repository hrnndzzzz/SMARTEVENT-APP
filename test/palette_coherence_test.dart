import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/theme/app_colors.dart';

/// Every accent has four entries: the fill, the fill on a dark canvas,
/// the tint behind text, and the tint on a dark canvas. They are one
/// colour said four ways, so they have to be one *hue*.
///
/// This exists because changing one of the four is survivable for a
/// long time without anyone noticing. The restyle turned the brand
/// fill from blue to yellow and left the other three blue, so a primary
/// button was yellow in light and blue in dark, and a tinted brand
/// panel sat behind a yellow fill on a pale blue ground. Nothing failed.
/// The same thing had happened to mint, 37° toward olive.
///
/// Lightness and saturation are deliberately not checked: muting a
/// colour for the cream paper is the whole point of the light palette,
/// and holding a dark one down so it does not glow is the point of the
/// dark one. Only the hue is the identity.
void main() {
  const accents = <String, (Color, Color?, Color?, Color?)>{
    'brand': (
      AppColors.brand,
      AppColors.brandDark,
      AppColors.brandTint,
      AppColors.brandTintDark,
    ),
    'sun': (
      AppColors.sun,
      AppColors.sunDark,
      AppColors.sunTint,
      AppColors.sunTintDark,
    ),
    'mint': (
      AppColors.mint,
      AppColors.mintDark,
      AppColors.mintTint,
      AppColors.mintTintDark,
    ),
    'coral': (
      AppColors.coral,
      AppColors.coralDark,
      AppColors.coralTint,
      AppColors.coralTintDark,
    ),
    'orange': (
      AppColors.orange,
      AppColors.orangeDark,
      AppColors.orangeTint,
      AppColors.orangeTintDark,
    ),
    'violet': (
      AppColors.violet,
      AppColors.violetDark,
      AppColors.violetTint,
      AppColors.violetTintDark,
    ),
    'teal': (
      AppColors.teal,
      AppColors.tealDark,
      AppColors.tealTint,
      AppColors.tealTintDark,
    ),
    'leaf': (AppColors.leaf, AppColors.leafDark, null, null),
  };

  /// Degrees apart on the wheel, the short way round. Straight
  /// subtraction calls red at 2° and red at 358° half a turn apart.
  double gap(Color a, Color b) {
    final difference =
        (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs() % 360;
    return difference > 180 ? 360 - difference : difference;
  }

  accents.forEach((name, entry) {
    final (light, dark, tint, tintDark) = entry;

    test('$name is one hue in both themes', () {
      if (dark != null) {
        expect(
          gap(light, dark),
          lessThanOrEqualTo(15),
          reason: '$name and ${name}Dark are different colours',
        );
      }
      if (tint != null) {
        expect(
          gap(light, tint),
          lessThanOrEqualTo(15),
          reason: '$name and ${name}Tint are different colours',
        );
      }
      if (tintDark != null) {
        // Looser: a dark tint is the accent flattened against the navy
        // surface, which pulls it a little toward blue by construction.
        expect(
          gap(light, tintDark),
          lessThanOrEqualTo(22),
          reason: '$name and ${name}TintDark are different colours',
        );
      }
    });
  });

  test('the brand is blue', () {
    // SmartEvent is blue and orange — CITE's two, and the logo's two.
    // Said here rather than left to the four entries above agreeing
    // with each other, which they would have done just as happily at
    // any other hue.
    expect(
      HSLColor.fromColor(AppColors.brand).hue,
      inInclusiveRange(200, 240),
    );
    expect(
      HSLColor.fromColor(AppColors.orange).hue,
      inInclusiveRange(10, 40),
    );
  });

  test('a fill that carries ink is light enough to', () {
    // `foregroundOn` picks ink above 0.22 relative luminance. Every
    // light-theme accent is meant to be an ink-bearing fill, so one
    // that drops below the line silently turns its own labels white.
    for (final entry in accents.entries) {
      final light = entry.value.$1;
      expect(
        light.computeLuminance(),
        greaterThan(0.22),
        reason: '${entry.key} is too dark to carry ink',
      );
    }
  });
}
