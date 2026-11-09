import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';

/// The SmartEvent mark, on the ground it was drawn for.
///
/// The artwork exists twice because the phone outline is white in one
/// and navy in the other: neither one reads on the other's background,
/// so there is no single file that can be tinted into place. [BrandMark]
/// carries its own navy tile, which makes it correct in either theme
/// without asking the caller to think about it.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72, this.radius});

  /// Side of the tile, not of the mark: the artwork is inset so the
  /// arrow's point does not touch the corner.
  final double size;

  final BorderRadius? radius;

  /// The navy the mark was drawn on. Deliberately not a palette colour
  /// — the palette is the app's, this is the logo's, and a theme change
  /// must not repaint someone else's artwork underneath the mark.
  static const Color ground = Color(0xFF0C295A);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: radius ?? AppRadius.cardAll,
        // The palette's ink, not the constant: a border drawn in the
        // light theme's near-black disappears against the dark canvas,
        // and the tile loses the outline every other surface has.
        border: Border.all(
          color: context.palette.ink,
          width: AppBorders.width,
        ),
      ),
      child: Image.asset(
        'assets/brand/mark-on-dark.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // A missing asset should cost the logo, not the screen it is on.
        errorBuilder: (_, _, _) =>
            const Icon(Icons.event_available, color: Colors.white),
      ),
    );
  }
}
