import 'package:flutter/material.dart';
import 'app_colors.dart';

/// The colours that change with the theme, resolved from it.
///
/// Everything here flips between light and dark. The accents do not, and
/// so are read straight from [AppColors] — a yellow badge is the same
/// yellow in both themes.
///
/// The one rule worth stating: **ink is the foreground for the nearest
/// background, not a fixed colour.** On a dark canvas it is light, and
/// because the outlines and the hard shadows are the same mark as the
/// text, they turn light with it. Inside a bright accent fill it goes
/// back to being dark — `BrutSurface` handles that by measuring the fill
/// it was given, so it stays right however deeply things nest.
@immutable
class BrutPalette extends ThemeExtension<BrutPalette> {
  const BrutPalette({
    required this.canvas,
    required this.surface,
    required this.ink,
    required this.line,
    required this.muted,
    required this.subtle,
    required this.alertInk,
    required this.backdrop,
    required this.brandTint,
    required this.orangeTint,
    required this.sunTint,
    required this.mintTint,
    required this.coralTint,
  });

  final Color canvas;
  final Color surface;

  /// Text, outlines, icons and shadows on [canvas] and [surface].
  final Color ink;
  final Color line;
  final Color muted;
  final Color subtle;
  final Color alertInk;
  final Color backdrop;
  final Color brandTint;
  final Color orangeTint;
  final Color sunTint;
  final Color mintTint;
  final Color coralTint;

  static const BrutPalette lightPalette = BrutPalette(
    canvas: AppColors.canvas,
    surface: AppColors.surface,
    ink: AppColors.ink,
    line: AppColors.line,
    muted: AppColors.muted,
    subtle: AppColors.subtle,
    alertInk: AppColors.alertInk,
    backdrop: AppColors.backdrop,
    brandTint: AppColors.brandTint,
    orangeTint: AppColors.orangeTint,
    sunTint: AppColors.sunTint,
    mintTint: AppColors.mintTint,
    coralTint: AppColors.coralTint,
  );

  static const BrutPalette darkPalette = BrutPalette(
    canvas: AppColors.canvasDark,
    surface: AppColors.surfaceDark,
    ink: AppColors.inkDark,
    line: AppColors.lineDark,
    muted: AppColors.mutedDark,
    subtle: AppColors.subtleDark,
    alertInk: AppColors.alertInkDark,
    backdrop: AppColors.backdropDark,
    brandTint: AppColors.brandTintDark,
    orangeTint: AppColors.orangeTintDark,
    sunTint: AppColors.sunTintDark,
    mintTint: AppColors.mintTintDark,
    coralTint: AppColors.coralTintDark,
  );

  @override
  BrutPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? ink,
    Color? line,
    Color? muted,
    Color? subtle,
    Color? alertInk,
    Color? backdrop,
    Color? brandTint,
    Color? orangeTint,
    Color? sunTint,
    Color? mintTint,
    Color? coralTint,
  }) {
    return BrutPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      line: line ?? this.line,
      muted: muted ?? this.muted,
      subtle: subtle ?? this.subtle,
      alertInk: alertInk ?? this.alertInk,
      backdrop: backdrop ?? this.backdrop,
      brandTint: brandTint ?? this.brandTint,
      orangeTint: orangeTint ?? this.orangeTint,
      sunTint: sunTint ?? this.sunTint,
      mintTint: mintTint ?? this.mintTint,
      coralTint: coralTint ?? this.coralTint,
    );
  }

  @override
  BrutPalette lerp(BrutPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return BrutPalette(
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      ink: mix(ink, other.ink),
      line: mix(line, other.line),
      muted: mix(muted, other.muted),
      subtle: mix(subtle, other.subtle),
      alertInk: mix(alertInk, other.alertInk),
      backdrop: mix(backdrop, other.backdrop),
      brandTint: mix(brandTint, other.brandTint),
      orangeTint: mix(orangeTint, other.orangeTint),
      sunTint: mix(sunTint, other.sunTint),
      mintTint: mix(mintTint, other.mintTint),
      coralTint: mix(coralTint, other.coralTint),
    );
  }
}

extension BrutPaletteOf on BuildContext {
  /// The theme's flipping colours. Falls back to the light set so a
  /// widget built outside a themed subtree still renders.
  BrutPalette get palette =>
      Theme.of(this).extension<BrutPalette>() ?? BrutPalette.lightPalette;

  /// The outline every container and control wears.
  BorderSide get side => BorderSide(color: palette.ink, width: 2);

  /// The foreground that belongs on [fill]: dark ink on anything bright
  /// enough to carry it, light ink otherwise. Measured rather than
  /// declared, so it is right for colours this file has never heard of.
  ///
  /// The threshold sits at 0.22 because that is the gap between the two
  /// groups it has to separate. Coral is the darkest accent at 0.30 and
  /// still needs dark ink on it (5.7:1, against 2.6:1 the other way); the
  /// dark theme's yellow tint is the lightest surface that needs light
  /// ink, at 0.13. Anywhere in between works; the middle is the safest
  /// place to stand.
  Color foregroundOn(Color fill) =>
      fill.computeLuminance() > 0.22 ? AppColors.ink : AppColors.inkDark;
}

extension BrutShapeOf on BuildContext {
  /// The outline, as a whole border.
  Border get borderAll => Border.fromBorderSide(side);
  Border get borderTop => Border(top: side);
  Border get borderBottom => Border(bottom: side);

  /// A disabled control's outline: present, but clearly not live.
  BorderSide get disabledSide => BorderSide(color: palette.muted, width: 2);

  /// Re-inks a shadow from [AppShadows] for the current theme, keeping its
  /// offset. On a dark canvas the shadow is light, because it is the same
  /// mark as the text.
  List<BoxShadow> shadows(List<BoxShadow> base) => [
    for (final b in base)
      BoxShadow(color: palette.ink, offset: b.offset, blurRadius: 0),
  ];
}
