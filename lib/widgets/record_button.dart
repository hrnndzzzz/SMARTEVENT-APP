import 'package:flutter/material.dart';

import '../screens/scanner_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Record an expense: the one thing the dashboard is for doing rather
/// than reading.
///
/// It sits in a band of its own between the dashboard and the
/// navigation bar, overlapping neither.
///
/// Floating over the dashboard it covered the allocated and spent
/// figures whenever the screen was at rest, and padding could not fix
/// that: a floating button over a scrolling list covers whatever is
/// under it, and the bottom padding only clears the last card at full
/// scroll. Docked into the bar instead, it punched through the bar's
/// own edge and read as a collision. A band costs the dashboard about
/// eighty pixels and collides with nothing.
class RecordButton extends StatelessWidget {
  const RecordButton({super.key});

  /// The side of the circle.
  static const double size = 68;

  @override
  Widget build(BuildContext context) {
    return BrutSurface(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ScannerScreen())),
      semanticLabel: 'Record an expense',
      fill: AppColors.orange,
      radius: AppRadius.pill,
      shadow: AppShadows.lg,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: const Icon(
        Icons.document_scanner_outlined,
        size: 28,
        color: AppColors.ink,
      ),
    );
  }
}
