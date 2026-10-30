import 'package:flutter/material.dart';

import '../screens/scanner_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Record an expense: the one thing the dashboard is for doing rather
/// than reading.
///
/// It lives above the navigation bar rather than floating over the
/// dashboard. Floating, it covered the allocated and spent figures
/// whenever the screen was at rest — a floating button over a scrolling
/// list always covers something, and padding only clears the last card
/// at full scroll. Docked here it overlaps the navigation it sits on and
/// nothing that carries a number.
class RecordButton extends StatelessWidget {
  const RecordButton({super.key});

  /// How far it rises above the bar it is docked to.
  ///
  /// Measured, not chosen: at 22 the circle clipped the tail of
  /// "REMAINING BUDGET" on a 1080x2400 phone. This clears it.
  static const double overlap = 14;

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
