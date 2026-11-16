import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/avatar.dart';
import 'package:smartevent/theme/app_colors.dart';
import 'package:smartevent/theme/module_identity.dart';

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

  // ─────────────────────────────────────────────────────────────────
  // How loud a colour is allowed to be.
  //
  // These are the rules `AppColors` states in prose, said again as
  // numbers. They exist because the complaint that produced them —
  // "the colours are over-saturated, especially in dark mode they look
  // really bright" — is not something a test can be asked for directly,
  // but every part of it turned out to be measurable.
  // ─────────────────────────────────────────────────────────────────

  double saturation(Color c) => HSLColor.fromColor(c).saturation;

  /// Contrast, the WCAG way, so "readable" is a number and not a guess.
  double contrast(Color a, Color b) {
    final x = a.computeLuminance();
    final y = b.computeLuminance();
    final hi = x > y ? x : y;
    final lo = x > y ? y : x;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('nothing is louder than the cap', () {
    // `alert` is the exception, and the only one: it is the colour on
    // the button that deletes the thing. `leaf` is six pixels of "on"
    // rather than a field, so it is not in these lists either.
    const lightFills = <String, Color>{
      'brand': AppColors.brand,
      'sun': AppColors.sun,
      'mint': AppColors.mint,
      'coral': AppColors.coral,
      'orange': AppColors.orange,
      'violet': AppColors.violet,
      'teal': AppColors.teal,
    };

    lightFills.forEach((name, colour) {
      test('$name is within the light cap', () {
        expect(
          saturation(colour),
          lessThanOrEqualTo(AppColors.lightSaturationCap + 0.01),
          reason: '$name is at full strength on the cream',
        );
      });
    });

    test('every module on the cream is within it too', () {
      for (final module in Module.values) {
        expect(
          saturation(module.color),
          lessThanOrEqualTo(AppColors.lightSaturationCap + 0.01),
          reason: '${module.name} is at full strength',
        );
      }
    });

    test('and on the navy, within the lower one', () {
      const darkFills = <String, Color>{
        'brandDark': AppColors.brandDark,
        'sunDark': AppColors.sunDark,
        'mintDark': AppColors.mintDark,
        'coralDark': AppColors.coralDark,
        'orangeDark': AppColors.orangeDark,
        'violetDark': AppColors.violetDark,
        'tealDark': AppColors.tealDark,
      };
      darkFills.forEach((name, colour) {
        expect(
          saturation(colour),
          lessThanOrEqualTo(AppColors.darkSaturationCap + 0.01),
          reason: '$name has not been held down for the dark canvas',
        );
      });
      for (final module in Module.values) {
        expect(
          saturation(module.colorDark),
          lessThanOrEqualTo(AppColors.darkSaturationCap + 0.01),
          reason: '${module.name} has not been held down',
        );
      }
    });

    test('an avatar ground is within the cap and still carries its initials', () {
      // They do not follow the theme — a face that changed colour with
      // the time of day would not read as the same person — so nothing
      // else holds them down, and four of them were pure hues.
      for (final value in avatarColors) {
        final ground = Color(value);
        expect(
          saturation(ground),
          lessThanOrEqualTo(AppColors.lightSaturationCap + 0.01),
          reason: '${ground.toARGB32().toRadixString(16)} is at full strength',
        );
        expect(
          contrast(ground, AppColors.ink),
          greaterThanOrEqualTo(4.5),
          reason: 'dark initials have to stay readable on it',
        );
      }
    });
  });

  group('the dark canvas has two bands, and neither straddles the line', () {
    // `foregroundOn` picks the ink by measuring the fill against 0.22.
    // A set of fills scattered across that number is a set that prints
    // its labels in two colours, which is what the dark menu did: the
    // Analytics block at 0.37 with dark text beside the Inventory block
    // at 0.19 with light text.
    const threshold = 0.22;

    test('every chip, badge and button fill sits above it', () {
      const small = <String, Color>{
        'brandDark': AppColors.brandDark,
        'sunDark': AppColors.sunDark,
        'mintDark': AppColors.mintDark,
        'coralDark': AppColors.coralDark,
        'orangeDark': AppColors.orangeDark,
        'violetDark': AppColors.violetDark,
        'tealDark': AppColors.tealDark,
        'leafDark': AppColors.leafDark,
        'alert': AppColors.alert,
      };
      small.forEach((name, colour) {
        expect(
          colour.computeLuminance(),
          greaterThan(threshold),
          reason: '$name would take light ink while its neighbours take dark',
        );
      });
    });

    test('every band and menu block sits below it', () {
      for (final module in Module.values) {
        expect(
          module.colorDark.computeLuminance(),
          lessThan(threshold),
          reason: '${module.name} would take dark ink while its neighbours '
              'take light — and would be the brightest thing on the screen',
        );
      }
    });

    test('and the small text printed on a block still reads', () {
      // The whole reason the band is as dim as it is. 0.145 is as
      // bright as it can be and keep this above 4.5:1.
      for (final module in Module.values) {
        expect(
          contrast(module.colorDark, AppColors.inkDark),
          greaterThanOrEqualTo(4.5),
          reason: "${module.name}'s subtitle is too faint on it",
        );
      }
    });
  });

  group('the dark palette is the light one, held down by one rule', () {
    // Written out as constants, because a `const` cannot call a
    // function — so this is the only thing keeping the numbers and the
    // rule from drifting apart. The brand spent a whole restyle being
    // yellow in one theme and blue in the other for want of exactly
    // this check.
    const derived = <String, (Color, Color)>{
      'brand': (AppColors.brand, AppColors.brandDark),
      'sun': (AppColors.sun, AppColors.sunDark),
      'mint': (AppColors.mint, AppColors.mintDark),
      'orange': (AppColors.orange, AppColors.orangeDark),
      'violet': (AppColors.violet, AppColors.violetDark),
      'teal': (AppColors.teal, AppColors.tealDark),
    };

    derived.forEach((name, pair) {
      final (light, dark) = pair;
      test('${name}Dark is onDarkCanvas($name)', () {
        expect(AppColors.onDarkCanvas(light), dark);
      });
    });

    test('every module band is onDarkCanvas of its own colour', () {
      for (final module in Module.values) {
        expect(
          AppColors.onDarkCanvas(
            module.color,
            luminance: AppColors.darkBandLuminance,
          ),
          module.colorDark,
          reason: '${module.name} has been set by hand',
        );
      }
    });

    test('coral keeps its own hue, 26° clear of orange', () {
      // The one accent not derived from its light twin. Run through the
      // rule, coral comes out 13° from orange at the same saturation and
      // the same brightness — which is to say, the same colour. At that
      // point "rejected" and "CITE" are one swatch.
      expect(
        gap(AppColors.coralDark, AppColors.orangeDark),
        greaterThan(20),
        reason: 'a problem and a department look the same on the navy',
      );
      expect(gap(AppColors.coralDark, AppColors.coral), lessThanOrEqualTo(15));
    });

    test('holding a colour down does not move its hue', () {
      // The point of the exercise is a quieter palette, not a different
      // one. Anything else and this is a recolour.
      for (final accent in AppColors.accents) {
        expect(
          gap(accent, AppColors.onDarkCanvas(accent)),
          lessThanOrEqualTo(2),
          reason: 'onDarkCanvas changed the colour rather than its strength',
        );
      }
    });

    test('an unknown department colour is held down the same way', () {
      // The reason this is a function at all: the accent reaches
      // AppTheme from the signed-in account, so there is no constant
      // waiting for it, and it used to arrive at full strength.
      const custom = Color(0xFFFF00AA);
      final held = AppColors.onDarkCanvas(custom);
      expect(
        saturation(held),
        lessThanOrEqualTo(AppColors.darkSaturationCap + 0.01),
      );
      expect(
        held.computeLuminance(),
        closeTo(AppColors.darkAccentLuminance, 0.005),
      );
    });
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
