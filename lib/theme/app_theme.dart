import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Type scale — Lexend main font natin hihi, IBM Plex Mono for
/// numbers (peso amounts, quantities, timestamps). Naka register na sa
///  pubspec.yaml rawr.
class AppText {
  AppText._();

  static const String headerFamily = 'Lexend';
  static const String bodyFamily = 'Lexend';
  static const String monoFamily = 'IBMPlexMono';

  static const TextStyle wordmark = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w500,
    fontSize: 17,
    color: AppColors.indigo,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    color: AppColors.ink,
  );

  static const TextStyle body = TextStyle(
    fontFamily: bodyFamily,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    color: AppColors.ink,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: bodyFamily,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    color: AppColors.inkMuted,
  );

  static const TextStyle navLabel = TextStyle(
    fontFamily: bodyFamily,
    fontWeight: FontWeight.w500,
    fontSize: 10,
  );

  /// Use for every peso amount, quantity, and timestamp.
  static const TextStyle moneyLarge = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w500,
    fontSize: 21,
    color: AppColors.ink,
  );

  static const TextStyle moneySmall = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w400,
    fontSize: 11,
    color: AppColors.inkMuted,
  );
}

class AppTheme {
  AppTheme._();

  /// [primary] defaults to the app's original indigo, but can be
  /// overridden to reflect the signed-in account's department color
  /// (see AppState.themeColor) — a visual demo of how SmartEvent could
  /// theme itself per college if this were ever scaled campus-wide.
  static ThemeData light({Color primary = AppColors.indigo}) {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: AppText.bodyFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: AppColors.marigold,
        tertiary: AppColors.sageTeal,
        error: AppColors.brick,
        surface: AppColors.surface,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: AppText.bodyFamily,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.border, width: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: AppText.bodyFamily,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}