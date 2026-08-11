import 'package:flutter/material.dart';

/// SmartEvent design tokens — "docket stub" palette.
/// Keep all raw hex values here; screens should reference these constants,
/// never hardcode Color(0x...) inline.
class AppColors {
  AppColors._();

  // Brand
  static const Color indigo = Color(0xFF2B3A67);
  static const Color indigoLightTint = Color(0xFFC9D1E3); // "allocated" bars, chips
  static const Color marigold = Color(0xFFE8A33D);
  static const Color marigoldTint = Color(0xFFF0EAD9);
  static const Color marigoldText = Color(0xFF7A4B0F);
  static const Color sageTeal = Color(0xFF3F8272);
  static const Color sageTealTint = Color(0xFFEAF3EE);
  static const Color sageTealBorder = Color(0xFFCFE3D8);
  static const Color sageTealText = Color(0xFF1F4A3F);
  static const Color brick = Color(0xFFC1503D);

  // Neutrals
  static const Color background = Color(0xFFFAF8F3); // warm paper
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE5E1D6);
  static const Color trackBg = Color(0xFFEFEBE0); // progress bar track
  static const Color ink = Color(0xFF24262B); // primary text
  static const Color inkMuted = Color(0xFF6B6B63); // secondary text
  static const Color inkFaint = Color(0xFFB4B2A9); // inactive nav / faint labels
}
