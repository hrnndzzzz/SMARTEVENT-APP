import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Type scale.
///
/// The design calls for an extrabold geometric sans. We ship Lexend, which
/// is the right shape, but only at 400 and 500 — so a style asking for
/// `w800` currently renders at Medium, because Flutter falls back to the
/// nearest weight it actually has. The weights below are therefore written
/// as the design intends them: drop `Lexend-Bold.ttf` and
/// `Lexend-ExtraBold.ttf` into `fonts/`, declare them in `pubspec.yaml`,
/// and every heading in the app gets its real weight with no code change.
/// The same goes for `IBMPlexMono-SemiBold.ttf` and `-Bold.ttf`.
class AppText {
  AppText._();

  static const String headerFamily = 'Lexend';
  static const String bodyFamily = 'Lexend';
  static const String monoFamily = 'IBMPlexMono';

  /// Numbers line up in columns. Money that jitters between rows is
  /// harder to scan than money that doesn't.
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  // ── Headings ──────────────────────────────────────────────────────────

  /// The app name on the welcome and sign-in screens.
  static const TextStyle display = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w800,
    fontSize: 30,
    letterSpacing: -0.5,
    height: 1.1,
    color: AppColors.ink,
  );

  /// Big "done" and result states.
  static const TextStyle titleBig = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w800,
    fontSize: 23,
    letterSpacing: -0.3,
    height: 1.15,
    color: AppColors.ink,
  );

  /// Screen headers. One line, truncated.
  static const TextStyle screenTitle = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w800,
    fontSize: 17,
    color: AppColors.ink,
  );

  /// The SmartEvent wordmark. Sits inside the brand pill, so it is ink —
  /// never the department accent, which is a fill colour and far too light
  /// to read as text on the canvas.
  static const TextStyle wordmark = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w800,
    fontSize: 17,
    color: AppColors.ink,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w800,
    fontSize: 16,
    color: AppColors.ink,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w700,
    fontSize: 15,
    color: AppColors.ink,
  );

  // ── Body ──────────────────────────────────────────────────────────────

  static const TextStyle body = TextStyle(
    fontFamily: bodyFamily,
    fontWeight: FontWeight.w500,
    fontSize: 13.5,
    height: 1.4,
    color: AppColors.ink,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: bodyFamily,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.35,
    color: AppColors.subtle,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontFamily: bodyFamily,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    color: AppColors.ink,
  );

  static const TextStyle navLabel = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w600,
    fontSize: 9,
    letterSpacing: 0.6,
  );

  // ── Mono: eyebrows, meta, every number ────────────────────────────────

  /// The universal eyebrow. Uppercase the text at the call site, or use
  /// the `MonoLabel` widget, which does it for you.
  static const TextStyle monoLabel = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w600,
    fontSize: 10,
    letterSpacing: 1.2,
    color: AppColors.subtle,
  );

  /// Counts, quantities, dates inside rows.
  static const TextStyle number = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w800,
    fontSize: 13,
    fontFeatures: _tabular,
    color: AppColors.ink,
  );

  /// Use for every peso amount on a card.
  static const TextStyle moneyLarge = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w800,
    fontSize: 20,
    fontFeatures: _tabular,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );

  static const TextStyle moneySmall = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    fontFeatures: _tabular,
    color: AppColors.subtle,
  );

  /// The one number on the screen.
  static const TextStyle heroNumber = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w800,
    fontSize: 46,
    fontFeatures: _tabular,
    letterSpacing: -2,
    height: 1,
    color: AppColors.ink,
  );
}

/// Corner radii. Four values, no others: bigger thing, rounder corner.
class AppRadius {
  AppRadius._();

  /// Cards, sheets, big tiles.
  static const double card = 16;

  /// List rows, choice cards, metric tiles, toasts.
  static const double row = 12;

  /// Buttons, inputs, selects, chips, badges.
  static const double control = 8;

  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius rowAll = BorderRadius.all(Radius.circular(row));
  static const BorderRadius controlAll =
      BorderRadius.all(Radius.circular(control));

  /// Pills, switches, avatars, dots, progress bars.
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// Outlines. Everything interactive, and every container, gets this.
class AppBorders {
  AppBorders._();

  static const double width = 2;

  static const BorderSide side = BorderSide(color: AppColors.ink, width: width);
  static const BorderSide disabled =
      BorderSide(color: AppColors.muted, width: width);

  static const Border all = Border.fromBorderSide(side);
  static const Border top = Border(top: side);
  static const Border bottom = Border(bottom: side);
}

/// Hard offset shadows. Never blurred — `blurRadius` stays at zero, which
/// is the whole point of the style. A bigger offset means a more
/// important surface, and a pressed control has none at all.
class AppShadows {
  AppShadows._();

  /// Chips, list rows, small buttons inside cards.
  static const List<BoxShadow> sm = [
    BoxShadow(color: AppColors.shadow, offset: Offset(1, 1), blurRadius: 0),
  ];

  /// Buttons, cards, selected choices.
  static const List<BoxShadow> base = [
    BoxShadow(color: AppColors.shadow, offset: Offset(3, 3), blurRadius: 0),
  ];

  /// Sheets, menus, popovers.
  static const List<BoxShadow> lg = [
    BoxShadow(color: AppColors.shadow, offset: Offset(5, 5), blurRadius: 0),
  ];

  /// Pressed, and disabled.
  static const List<BoxShadow> none = <BoxShadow>[];

  /// How far a surface with [shadow] travels when pressed, so it lands
  /// exactly on the shadow it just lost.
  static Offset travelFor(List<BoxShadow> shadow) =>
      shadow.isEmpty ? Offset.zero : shadow.first.offset;
}

/// Motion. One duration for presses, one for things arriving.
class AppMotion {
  AppMotion._();

  static const Duration press = Duration(milliseconds: 80);
  static const Duration enter = Duration(milliseconds: 180);
  static const Duration sheet = Duration(milliseconds: 200);
  static const Duration accordion = Duration(milliseconds: 300);
}

class AppTheme {
  AppTheme._();

  /// [primary] defaults to the brand blue but is overridden with the
  /// signed-in account's department accent (see `AppState.themeColor`).
  /// It is always used as a *fill* with ink on top, never as text on the
  /// canvas — the accents are deliberately too light for that.
  static ThemeData light({Color primary = AppColors.brand}) {
    final textTheme = const TextTheme(
      displaySmall: AppText.display,
      headlineMedium: AppText.titleBig,
      titleLarge: AppText.screenTitle,
      titleMedium: AppText.cardTitle,
      titleSmall: AppText.sectionTitle,
      bodyMedium: AppText.body,
      bodySmall: AppText.caption,
      labelLarge: AppText.buttonLabel,
      labelSmall: AppText.monoLabel,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.canvas,
      fontFamily: AppText.bodyFamily,
      textTheme: textTheme,
      // Nothing in this design blurs, so the ripple goes too. Feedback is
      // the press offset instead.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        onPrimary: AppColors.ink,
        secondary: AppColors.sun,
        onSecondary: AppColors.ink,
        tertiary: AppColors.mint,
        onTertiary: AppColors.ink,
        error: AppColors.coral,
        onError: AppColors.ink,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        outline: AppColors.ink,
      ),
      iconTheme: const IconThemeData(color: AppColors.ink, size: 20),
      primaryIconTheme: const IconThemeData(color: AppColors.ink),
      dividerTheme: const DividerThemeData(
        color: AppColors.ink,
        thickness: AppBorders.width,
        space: AppBorders.width,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.screenTitle,
        shape: Border(bottom: AppBorders.side),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: AppBorders.side,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _filledStyle(primary),
      ),
      filledButtonTheme: FilledButtonThemeData(style: _filledStyle(primary)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _filledStyle(AppColors.surface),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: AppText.buttonLabel.copyWith(fontSize: 13),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        hintStyle: AppText.body.copyWith(color: AppColors.muted),
        labelStyle: AppText.body,
        // Error text is alertInk, not coral: coral is a fill colour and
        // does not have the contrast to be read at 12px.
        errorStyle: AppText.caption.copyWith(
          color: AppColors.alertInk,
          fontWeight: FontWeight.w600,
        ),
        border: _fieldBorder(AppColors.ink),
        enabledBorder: _fieldBorder(AppColors.ink),
        focusedBorder: _fieldBorder(AppColors.ink),
        disabledBorder: _fieldBorder(AppColors.muted),
        errorBorder: _fieldBorder(AppColors.ink),
        focusedErrorBorder: _fieldBorder(AppColors.ink),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: primary,
        disabledColor: AppColors.line,
        labelStyle: AppText.buttonLabel.copyWith(fontSize: 12),
        side: AppBorders.side,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.controlAll,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: AppText.body.copyWith(color: AppColors.surface),
        actionTextColor: AppColors.sun,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rowAll),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleTextStyle: AppText.cardTitle,
        contentTextStyle: AppText.body,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: AppBorders.side,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
          side: AppBorders.side,
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surface,
        elevation: 0,
        textStyle: AppText.body,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.rowAll,
          side: AppBorders.side,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.ink,
        textColor: AppColors.ink,
        titleTextStyle: AppText.body,
        subtitleTextStyle: AppText.caption,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(AppColors.surface),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.leaf
              : AppColors.line,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(AppColors.ink),
        trackOutlineWidth: const WidgetStatePropertyAll(AppBorders.width),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.leaf
              : AppColors.surface,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.ink),
        side: AppBorders.side,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.ink
              : AppColors.muted,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.ink,
        linearTrackColor: AppColors.line,
        circularTrackColor: AppColors.line,
        linearMinHeight: 12,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: AppColors.ink,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: AppBorders.side,
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.ink,
        selectionColor: AppColors.brandTint,
        selectionHandleColor: AppColors.ink,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: AppColors.ink,
          borderRadius: AppRadius.controlAll,
        ),
        textStyle: AppText.caption.copyWith(color: AppColors.surface),
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
        borderRadius: AppRadius.controlAll,
        borderSide: BorderSide(color: color, width: AppBorders.width),
      );

  /// Material's own buttons cannot draw a hard offset shadow — its
  /// elevation is always a blur — so a themed button is flat with a 2px
  /// outline. `BrutButton` in `brut.dart` is the one that sits on its
  /// shadow and drops onto it; use that for primary actions.
  static ButtonStyle _filledStyle(Color fill) => ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.line
              : fill,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.subtle
              : AppColors.ink,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppBorders.disabled
              : AppBorders.side,
        ),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        textStyle: const WidgetStatePropertyAll(AppText.buttonLabel),
        iconColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppColors.subtle
              : AppColors.ink,
        ),
        iconSize: const WidgetStatePropertyAll(18),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
        ),
      );
}
