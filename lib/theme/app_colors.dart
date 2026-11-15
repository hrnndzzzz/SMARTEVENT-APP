import 'package:flutter/material.dart';

/// SmartEvent design tokens — "soft-pop neo-brutalism".
///
/// Flat, bright colour blocks with thick dark outlines and hard offset
/// shadows, on a near-white canvas. Keep every raw hex in this file;
/// screens reference these constants and never write `Color(0x...)` inline.
///
/// The one rule that matters more than any value here: **one colour, one
/// meaning, everywhere.** Green is done. Coral is a problem. Yellow needs
/// a look. Blue is the brand and the primary action. A colour used
/// decoratively stops carrying information for every other screen.
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
  static const Color brand = Color(0xFF4D96FF);

  /// Needs attention, pending, waiting.
  ///
  /// The only yellow with a job. It was deepened to a gold when [brand]
  /// was briefly yellow too, because "waiting on a decision" and "press
  /// this" cannot be the same swatch. With the brand back to blue that
  /// collision is gone, and the gold stays: it is the one that reads on
  /// the cream.
  static const Color sun = Color(0xFFF2C230);

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
  static const Color leaf = Color(0xFF22C55E);

  /// Urgent, rejected, over budget, offline.
  static const Color coral = Color(0xFFE2543F);

  /// CITE's own orange. Added to the palette for the department rather
  /// than borrowing a status colour — it sits in the same soft-pop
  /// register and carries ink text at 7.3:1.
  static const Color orange = Color(0xFFF26B21);

  /// Rare. Destructive emphasis only.
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
  // The accents keep their light-theme hex: a yellow badge is the same
  // yellow in both themes, and still carries dark ink. What flips is the
  // canvas, and with it the ink — which means the outlines and the hard
  // shadows flip too, since they are the same mark as the text.
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

  // ── Department accents ────────────────────────────────────────────────
  // SmartEvent needs six distinguishable department colours. These extend
  // the palette in the same register (bright, light enough for ink text)
  // rather than reaching for the muted earth tones they replace.
  // The accents again, for a dark canvas.
  //
  // The same hues held down in lightness: at full strength a yellow card
  // on #121417 is a lamp, and three of them on one screen is all anyone
  // sees. These stay recognisably the same colour and stop glowing.
  // `foregroundOn` measures each one and picks the ink, so every value
  // here sits above its 0.22 threshold: three of them did not at first,
  // and one stack of bands came out reading two different ways.
  static const Color brandDark = Color(0xFF5C92DD);
  static const Color sunDark = Color(0xFFD4B43A);
  static const Color mintDark = Color(0xFF59A865);
  static const Color leafDark = Color(0xFF1E9E4D);
  static const Color coralDark = Color(0xFFD9636D);
  static const Color orangeDark = Color(0xFFD47334);
  static const Color violetDark = Color(0xFFA47FDD);
  static const Color tealDark = Color(0xFF35A7A0);

  static const Color violet = Color(0xFFB07BFF);
  static const Color teal = Color(0xFF3FC8C0);

  /// Every accent that may be used as a department or a grouping fill.
  ///
  /// [coral] is deliberately absent. It means "a problem" everywhere else
  /// in the app, so a department or a spending category wearing it would
  /// read as an error at a glance.
  static const List<Color> accents = [brand, orange, sun, mint, violet, teal];
}
