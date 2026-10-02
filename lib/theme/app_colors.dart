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
  static const Color canvas = Color(0xFFF8F9FA);

  /// Cards, inputs, sheets, neutral buttons.
  static const Color surface = Color(0xFFFFFFFF);

  /// Text, outlines, icons. Every border in the app is this colour.
  static const Color ink = Color(0xFF1A1A1A);

  /// Hard shadows. Same value as [ink] — they are the same mark.
  static const Color shadow = Color(0xFF1A1A1A);

  // ── Accents ───────────────────────────────────────────────────────────
  /// The brand, and every primary action.
  static const Color brand = Color(0xFF4D96FF);

  /// Needs attention, pending, waiting.
  static const Color sun = Color(0xFFFFD93D);

  /// Done, approved, correct.
  static const Color mint = Color(0xFF6BCB77);

  /// Small "on" signals only: a switch that is on, an online dot.
  static const Color leaf = Color(0xFF22C55E);

  /// Urgent, rejected, over budget, offline.
  static const Color coral = Color(0xFFFF5964);

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

  // ── Neutrals ──────────────────────────────────────────────────────────
  /// Disabled fills, progress tracks, hairline panels.
  static const Color line = Color(0xFFE2E8F0);

  /// Disabled borders and inactive icons.
  static const Color muted = Color(0xFF94A3B8);

  /// Secondary text and captions.
  static const Color subtle = Color(0xFF5B6472);

  /// Behind the phone-width column on a tablet or desktop window.
  static const Color backdrop = Color(0xFFE9ECEF);

  // ── Department accents ────────────────────────────────────────────────
  // SmartEvent needs six distinguishable department colours, two more than
  // the four accents above. These two extend the palette in the same
  // register (bright, light enough for ink text) rather than reaching for
  // the muted earth tones they replace.
  static const Color violet = Color(0xFFB07BFF);
  static const Color teal = Color(0xFF3FC8C0);

  /// Every accent that may be used as a department or area fill. Ink text
  /// is legible on all of them.
  static const List<Color> accents = [
    brand,
    sun,
    mint,
    coral,
    violet,
    teal,
  ];
}
