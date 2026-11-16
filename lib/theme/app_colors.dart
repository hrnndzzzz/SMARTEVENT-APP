import 'dart:math' as math;

import 'package:flutter/material.dart';

/// SmartEvent design tokens — "soft-pop neo-brutalism".
///
/// Flat colour blocks with thin dark outlines and hard offset shadows, on
/// a cream canvas. Keep every raw hex in this file; screens reference
/// these constants and never write `Color(0x...)` inline.
///
/// The one rule that matters more than any value here: **one colour, one
/// meaning, everywhere.** Green is done. Coral is a problem. Yellow needs
/// a look. Blue is the brand and the primary action. A colour used
/// decoratively stops carrying information for every other screen.
///
/// ## How loud a colour is allowed to be
///
/// Two numbers decide that, and both are enforced by
/// `test/palette_coherence_test.dart` rather than left to whoever edits
/// this file next.
///
/// **Saturation** is capped at [lightSaturationCap]. Nothing here is a
/// pure hue: at full strength four accents on one screen compete with the
/// content instead of labelling it, and the cream has no chance against
/// them. A colour already quieter than the cap is left where it is — the
/// cap only ever brings one down.
///
/// **Brightness** is set outright, because saturation is not the thing
/// that makes a screen glare. A fill goes into one of two bands by what
/// it is for, and `foregroundOn` reads the band back off it:
///
/// * Small marks — chips, badges, buttons, the department pill, the icon
///   block on a dashboard tile. They have to carry a signal, so they
///   stay above `foregroundOn`'s 0.22 line and take dark ink. On the
///   navy that is [darkAccentLuminance]; on the cream every accent was
///   already up there.
/// * Large fields — module bands and menu blocks. They go below the
///   line and take light ink, at [bandLuminance] in either theme.
///
/// Neither band touches the line, which is the whole point: a set of
/// fills scattered across it is a set that prints its labels in two
/// colours. Both themes did. On the navy the Analytics block sat at 0.37
/// and Inventory at 0.19, and the two warm ones were the brightest
/// things on the screen — brighter than the text on them. On the cream
/// it was quieter and exactly the same fault: Money at 0.28 and
/// Analytics at 0.24 carried dark ink while the other five carried
/// light, across one grid of seven menu blocks and one row of four
/// dashboard tiles.
class AppColors {
  AppColors._();

  // ── Canvas and ink ────────────────────────────────────────────────────
  /// Screen background.
  static const Color canvas = Color(0xFFF1E7D5);

  /// Cards, inputs, sheets, neutral buttons.
  static const Color surface = Color(0xFFFCF4E4);

  /// Text, outlines, icons. Every border in the app is this colour.
  static const Color ink = Color(0xFF14110C);

  /// Hard shadows. Same value as [ink] — they are the same mark.
  static const Color shadow = Color(0xFF1A1A1A);

  // ── How loud ──────────────────────────────────────────────────────────
  /// No accent or module fill is more saturated than this.
  static const double lightSaturationCap = 0.75;

  /// And on the navy, less again: a dark canvas has nothing to absorb a
  /// strong colour, so the same swatch that reads as a label on cream
  /// reads as a light source here.
  static const double darkSaturationCap = 0.50;

  /// Where a small dark-theme fill sits: above `foregroundOn`'s 0.22, so
  /// every chip and badge carries dark ink.
  static const double darkAccentLuminance = 0.27;

  /// Where a large field sits, on either canvas: below the line, so
  /// every band and menu block carries light ink.
  ///
  /// 0.145 is as bright as a block can be and still clear 4.5:1 against
  /// [inkDark] for the small text printed on it — and [inkDark] is the
  /// light ink in both themes, which is why one number does for both.
  ///
  /// On the navy it is a value: every band is set to it exactly, because
  /// every band there is derived. On the cream it is a *ceiling*, and
  /// only the two that were over it came down. Holding the other five up
  /// to it would have made Inventory, Flagged, Administration and Search
  /// brighter than they already are, which is the opposite of what was
  /// asked for.
  static const double bandLuminance = 0.145;

  // ── Accents ───────────────────────────────────────────────────────────
  /// The brand, and every primary action. Blue.
  ///
  /// SmartEvent is blue and orange — CITE's two, and the logo's two —
  /// and the restyle quietly made this half yellow. Three places went
  /// on saying blue while it did: [brandDark], so a primary button was
  /// yellow in light and blue in dark; [brandTint], so a tinted brand
  /// panel sat behind a yellow fill; and AppTheme's own doc, which says
  /// primary "stays blue". One of the four was changed, which is the
  /// kind of thing a palette cannot survive.
  static const Color brand = Color(0xFF639AE9);

  /// Needs attention, pending, waiting.
  ///
  /// The only yellow with a job. It was deepened to a gold when [brand]
  /// was briefly yellow too, because "waiting on a decision" and "press
  /// this" cannot be the same swatch. With the brand back to blue that
  /// collision is gone, and the gold stays: it is the one that reads on
  /// the cream.
  static const Color sun = Color(0xFFE3BB3F);

  /// Done, approved, correct.
  ///
  /// The same drift as [brand], caught by the same measurement: muting
  /// this for the cream rotated it 37° into yellow-green while
  /// [mintDark] and [mintTint] stayed at the green they always were,
  /// so "approved" was olive in light and green in dark. Back on the
  /// family's own hue, at the saturation and lightness the cream
  /// needed.
  static const Color mint = Color(0xFF6AB472);

  /// Small "on" signals only: a switch that is on, an online dot.
  ///
  /// Outside the rules above, in both themes. It is never a field with
  /// something written on it — it is six pixels across, and six pixels
  /// of a held-down colour is six pixels of nothing.
  static const Color leaf = Color(0xFF22C55E);

  /// Urgent, rejected, over budget, offline.
  static const Color coral = Color(0xFFE2543F);

  /// CITE's own orange. Added to the palette for the department rather
  /// than borrowing a status colour — it sits in the same soft-pop
  /// register and carries ink text at 5.9:1.
  static const Color orange = Color(0xFFE27031);

  /// Rare. Destructive emphasis only.
  ///
  /// The one accent exempt from [lightSaturationCap]: this is the colour
  /// on the button that deletes the thing, and a red that has been
  /// calmed down to sit politely in the palette is not doing its job.
  static const Color alert = Color(0xFFEF4444);

  /// Error *text* on light backgrounds. [coral] is too light to read.
  static const Color alertInk = Color(0xFFB42318);

  // ── Soft tints ────────────────────────────────────────────────────────
  // The accents flattened against white, for backgrounds behind text.
  // Ink stays legible on all four — that is why they exist.
  static const Color brandTint = Color(0xFFD2E5FF);
  static const Color sunTint = Color(0xFFFFF2BB);
  static const Color mintTint = Color(0xFFD3EFD6);
  static const Color coralTint = Color(0xFFFFDADD);
  static const Color orangeTint = Color(0xFFFFE2CD);
  static const Color violetTint = Color(0xFFEBDEFF);
  static const Color tealTint = Color(0xFFC5EEEC);

  // ── Neutrals ──────────────────────────────────────────────────────────
  /// Disabled fills, progress tracks, hairline panels.
  /// Not only a rule. This is also the fill behind a progress bar, the
  /// unreached half of a step bar and a disabled chip, so it has to stay
  /// light: setting it to the outline colour turned every track black.
  static const Color line = Color(0xFFE3D9C6);

  /// Disabled borders and inactive icons.
  static const Color muted = Color(0xFF94A3B8);

  /// Secondary text and captions.
  static const Color subtle = Color(0xFF5B6472);

  /// Behind the phone-width column on a tablet or desktop window.
  static const Color backdrop = Color(0xFFE9ECEF);

  // ── Dark theme ────────────────────────────────────────────────────────
  /// Navy, not near-black. The logo is drawn on #0C295A, so the dark
  /// theme sits in the same family rather than in a neutral grey that
  /// belongs to nothing.
  static const Color canvasDark = Color(0xFF0C1F3D);
  static const Color surfaceDark = Color(0xFF14294A);
  static const Color inkDark = Color(0xFFEDF2F9);
  static const Color lineDark = Color(0xFF27446E);
  static const Color mutedDark = Color(0xFF6E82A3);
  static const Color subtleDark = Color(0xFFA6B6CE);
  static const Color alertInkDark = Color(0xFFFF8A8F);
  static const Color backdropDark = Color(0xFF060F1E);

  // The tints are the accents flattened against the dark surface rather
  // than against white, so a tinted panel stays a panel instead of
  // becoming the brightest thing on a dark screen.
  static const Color brandTintDark = Color(0xFF2A405F);
  static const Color orangeTintDark = Color(0xFF63422F);
  static const Color sunTintDark = Color(0xFF6D6330);
  static const Color mintTintDark = Color(0xFF365641);
  static const Color coralTintDark = Color(0xFF573038);
  static const Color violetTintDark = Color(0xFF43395F);
  static const Color tealTintDark = Color(0xFF295557);

  // The accents again, for a dark canvas: each one is [onDarkCanvas] of
  // the light value above it, written out because a `const` cannot call
  // a function. The test checks that they still agree, so the rule and
  // the numbers cannot quietly come apart.
  static const Color brandDark = Color(0xFF6590CC);
  static const Color sunDark = Color(0xFFA78C38);
  static const Color mintDark = Color(0xFF509F58);
  static const Color orangeDark = Color(0xFFC67C53);
  static const Color violetDark = Color(0xFFA07DD4);
  static const Color tealDark = Color(0xFF349D96);

  /// Coral on the navy, held to the same saturation and brightness as the
  /// rest — but kept at its own pinker hue rather than taking [coral]'s.
  ///
  /// At one saturation and one brightness, hue is all that is left to
  /// tell two colours apart, and coral and [orange] are 13° apart. Run
  /// through the rule from its light value this came out a terracotta
  /// all but identical to [orangeDark], which would have made "rejected"
  /// and "CITE" the same swatch. 26° is enough; 13° is not.
  static const Color coralDark = Color(0xFFD0727A);

  /// The dot again, untouched. See [leaf].
  static const Color leafDark = Color(0xFF1E9E4D);

  static const Color violet = Color(0xFFB38CEE);
  static const Color teal = Color(0xFF3FC8C0);

  /// Every accent that may be used as a department or a grouping fill.
  ///
  /// [coral] is deliberately absent. It means "a problem" everywhere else
  /// in the app, so a department or a spending category wearing it would
  /// read as an error at a glance.
  static const List<Color> accents = [brand, orange, sun, mint, violet, teal];

  /// What [accent] becomes on the navy: same hue, saturation held to
  /// [darkSaturationCap], brightness set to [luminance].
  ///
  /// The constants above are this function's output. It exists as a
  /// function for the one accent that cannot be one of them — the
  /// department colour, which arrives at `AppTheme.dark` from the
  /// signed-in account. Before this it arrived at full light-theme
  /// strength, so on CITE's dark dashboard the brand pill, the avatar,
  /// the peso figure and the budget bar were all the bright orange while
  /// every other accent on the screen had been held down.
  static Color onDarkCanvas(Color accent, {double? luminance}) =>
      _hold(accent, luminance ?? darkAccentLuminance, darkSaturationCap);

  /// What [accent] becomes as a large field on the cream: the same hue,
  /// its saturation up to [lightSaturationCap], and its brightness
  /// brought down to [bandLuminance] if it was over it.
  ///
  /// The light twin of [onDarkCanvas], and a ceiling rather than a
  /// setting — a colour already within both rules is handed back
  /// untouched rather than put through the round trip, so five of the
  /// seven module colours are literally unchanged by it.
  static Color bandOnCream(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    if (hsl.saturation <= lightSaturationCap &&
        accent.computeLuminance() <= bandLuminance) {
      return accent;
    }
    return _hold(accent, bandLuminance, lightSaturationCap);
  }

  static final Map<(int, double, double), Color> _held = {};

  static Color _hold(Color accent, double target, double cap) {
    final key = (accent.toARGB32(), target, cap);
    return _held[key] ??= _solve(accent, target, cap);
  }

  /// Bisection, because relative luminance has no closed form in HSL.
  /// Twenty-four halvings of [0, 1] land inside a 24-bit colour's own
  /// precision, so the result is exact for this purpose and stable.
  ///
  /// [cap] is part of the memo key as well as the maths: the two callers
  /// ask for the same [bandLuminance] under different caps, and keying
  /// on the target alone would have handed one of them the other's
  /// answer.
  static Color _solve(Color accent, double target, double cap) {
    final hsl = HSLColor.fromColor(accent);
    final held = hsl.withSaturation(math.min(hsl.saturation, cap));
    var low = 0.0;
    var high = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (low + high) / 2;
      if (held.withLightness(mid).toColor().computeLuminance() < target) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return held.withLightness((low + high) / 2).toColor();
  }
}
