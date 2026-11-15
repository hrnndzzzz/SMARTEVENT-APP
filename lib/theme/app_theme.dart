import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'palette.dart';

/// Type scale.
///
/// None of these carries a colour. `Text` merges the nearest
/// `DefaultTextStyle` with the style it is given, so leaving the colour
/// out lets it come from the surface the text is sitting on — the theme's
/// ink on a canvas, dark ink inside a yellow badge — however deeply things
/// nest. Setting it here would freeze every caption at light-mode grey.
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

  static const String headerFamily = 'IBMPlexMono';
  static const String bodyFamily = 'Lexend';
  static const String monoFamily = 'IBMPlexMono';

  /// Numbers line up in columns. Money that jitters between rows is
  /// harder to scan than money that doesn't.
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  // ── Headings ──────────────────────────────────────────────────────────

  /// **Every screen's own title**, and the app name on welcome and
  /// sign-in. One size for the thing at the top of a page, so Income and
  /// Expenses do not announce themselves at half and full volume when
  /// they sit one tap apart under the same hub. Wraps rather than
  /// truncating, which is why it carries a line height.
  static const TextStyle display = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w800,
    fontSize: 30,
    letterSpacing: -0.5,
    height: 1.1,
  );

  /// Big "done" and result states.
  static const TextStyle titleBig = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w800,
    fontSize: 23,
    letterSpacing: -0.3,
    height: 1.15,
  );

  /// Titles *inside* a surface — a sheet's heading, an AppBar — where the
  /// surface is already the frame and a page-sized title would shout.
  /// Not for a screen's own title: that is [display].
  static const TextStyle screenTitle = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w800,
    fontSize: 17,
  );

  /// The SmartEvent wordmark. Sits inside the brand pill, so it is ink —
  /// never the department accent, which is a fill colour and far too light
  /// to read as text on the canvas.
  static const TextStyle wordmark = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w800,
    fontSize: 17,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w800,
    fontSize: 16,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: headerFamily,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  // ── Body ──────────────────────────────────────────────────────────────

  static const TextStyle body = TextStyle(
    fontFamily: bodyFamily,
    fontWeight: FontWeight.w500,
    fontSize: 13.5,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: bodyFamily,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.35,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontFamily: bodyFamily,
    fontWeight: FontWeight.w700,
    fontSize: 14,
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
  );

  /// Counts, quantities, dates inside rows.
  static const TextStyle number = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w800,
    fontSize: 13,
    fontFeatures: _tabular,
  );

  /// Use for every peso amount on a card.
  static const TextStyle moneyLarge = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w800,
    fontSize: 20,
    fontFeatures: _tabular,
    letterSpacing: -0.5,
  );

  static const TextStyle moneySmall = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    fontFeatures: _tabular,
  );

  /// The one number on the screen.
  static const TextStyle heroNumber = TextStyle(
    fontFamily: monoFamily,
    fontWeight: FontWeight.w800,
    fontSize: 46,
    fontFeatures: _tabular,
    letterSpacing: -2,
    height: 1,
  );
}

/// Corner radii. Four values, no others: bigger thing, rounder corner.
class AppRadius {
  AppRadius._();

  /// Cards, sheets, big tiles.
  static const double card = 6;

  /// List rows, choice cards, metric tiles, toasts.
  static const double row = 12;

  /// Buttons, inputs, selects, chips, badges.
  static const double control = 4;

  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius rowAll = BorderRadius.all(Radius.circular(row));
  static const BorderRadius controlAll = BorderRadius.all(
    Radius.circular(control),
  );

  /// Pills, switches, avatars, dots, progress bars.
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// Outlines. Everything interactive, and every container, gets this.
///
/// The constants here are the light-theme values. Anything that has a
/// `BuildContext` should use `context.side`, `context.borderAll` and
/// friends instead, so the outline flips with the canvas — on a dark
/// screen the outlines are light, because they are the same mark as the
/// text.
class AppBorders {
  AppBorders._();

  static const double width = 2;

  static const BorderSide side = BorderSide(color: AppColors.ink, width: width);
  static const BorderSide disabled = BorderSide(
    color: AppColors.muted,
    width: width,
  );

  static const Border all = Border.fromBorderSide(side);
  static const Border top = Border(top: side);
  static const Border bottom = Border(bottom: side);
}

/// Hard offset shadows. Never blurred — `blurRadius` stays at zero, which
/// is the whole point of the style. A bigger offset means a more
/// important surface, and a pressed control has none at all.
///
/// These carry the light-theme ink. `BrutSurface` re-inks whatever it is
/// given from the theme, so a call site can keep passing `AppShadows.base`
/// and still get a light shadow on a dark canvas; outside the kit, use
/// `context.shadows(AppShadows.base)`.
class AppShadows {
  AppShadows._();

  /// Chips, list rows, small buttons inside cards.
  static const List<BoxShadow> sm = [];

  /// Buttons, cards, selected choices.
  static const List<BoxShadow> base = [];

  /// Sheets, menus, popovers.
  static const List<BoxShadow> lg = [];

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

  /// Things arriving: a little overshoot at the end, so a panel lands
  /// rather than stopping dead. Decelerating alone reads as the frame
  /// rate giving out.
  static const Curve arriving = Curves.easeOutCubic;

  /// Things leaving. Faster at the start, because nobody watches an
  /// exit — they are already looking at what comes next.
  static const Curve leaving = Curves.easeInCubic;

  /// Opening and closing in place: an accordion, a disclosure. Eased at
  /// both ends, since the eye follows the whole movement.
  static const Curve inPlace = Curves.easeInOutCubic;

  /// A press. Nearly instant, and linear at this length — a curve over
  /// 80ms is a curve nobody perceives.
  static const Curve pressed = Curves.linear;
}

class AppTheme {
  AppTheme._();

  /// [primary] is the colour of a primary action, and stays blue: one
  /// colour, one meaning, and blue means "this is the action".
  ///
  /// [accent] is the signed-in account's department (see
  /// `AppState.themeColor`). It identifies whose records you are looking
  /// at — the brand pill, the avatar, the active nav tab — and is reached
  /// through `colorScheme.secondary`. Both are always used as *fills*
  /// with ink on top, never as text on the canvas: the palette is
  /// deliberately too light for that.
  static ThemeData light({
    Color primary = AppColors.brand,
    Color accent = AppColors.brand,
  }) => _build(Brightness.light, primary, accent);

  /// The same theme on a dark canvas.
  ///
  /// The accents keep their hex — a yellow badge is the same yellow — and
  /// still carry dark ink. What flips is the canvas, the text, and with
  /// them the outlines and the hard shadows, which are the same mark as
  /// the text and would vanish if they stayed dark.
  static ThemeData dark({
    Color primary = AppColors.brand,
    Color accent = AppColors.brand,
  }) => _build(Brightness.dark, primary, accent);

  static ThemeData _build(Brightness brightness, Color primary, Color accent) {
    final isDark = brightness == Brightness.dark;
    final p = isDark ? BrutPalette.darkPalette : BrutPalette.lightPalette;
    final side = BorderSide(color: p.ink, width: AppBorders.width);
    final disabledSide = BorderSide(color: p.muted, width: AppBorders.width);

    OutlineInputBorder fieldBorder(Color color) => OutlineInputBorder(
      borderRadius: AppRadius.controlAll,
      borderSide: BorderSide(color: color, width: AppBorders.width),
    );

    /// Material's own buttons cannot draw a hard offset shadow — its
    /// elevation is always a blur — so a themed button is flat with a 2px
    /// outline. `BrutButton` in `brut.dart` is the one that sits on its
    /// shadow and drops onto it; use that for primary actions.
    ButtonStyle filled(Color fill) => ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? p.line : fill,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? p.subtle
            // Ink on a bright fill, the theme's ink on a neutral one.
            : (fill.computeLuminance() > 0.45 ? AppColors.ink : p.ink),
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? disabledSide : side,
      ),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      textStyle: const WidgetStatePropertyAll(AppText.buttonLabel),
      iconSize: const WidgetStatePropertyAll(18),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
      ),
    );

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
    ).apply(bodyColor: p.ink, displayColor: p.ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      fontFamily: AppText.bodyFamily,
      textTheme: textTheme,
      extensions: [p],
      // Nothing in this design blurs, so the ripple goes too. Feedback is
      // the press offset instead.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        primary: primary,
        onPrimary: AppColors.ink,
        secondary: accent,
        onSecondary: AppColors.ink,
        tertiary: AppColors.mint,
        onTertiary: AppColors.ink,
        error: AppColors.coral,
        onError: AppColors.ink,
        surface: p.surface,
        onSurface: p.ink,
        outline: p.ink,
      ),
      iconTheme: IconThemeData(color: p.ink, size: 20),
      primaryIconTheme: IconThemeData(color: p.ink),
      dividerTheme: DividerThemeData(
        color: p.ink,
        thickness: AppBorders.width,
        space: AppBorders.width,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.screenTitle.copyWith(color: p.ink),
        shape: Border(bottom: side),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: side,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: filled(primary)),
      filledButtonTheme: FilledButtonThemeData(style: filled(primary)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: filled(p.surface)),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.ink,
          textStyle: AppText.buttonLabel.copyWith(fontSize: 13),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
        hintStyle: AppText.body.copyWith(color: p.muted),
        labelStyle: AppText.body.copyWith(color: p.ink),
        // Error text is alertInk, not coral: coral is a fill colour and
        // does not have the contrast to be read at 12px.
        errorStyle: AppText.caption.copyWith(
          color: p.alertInk,
          fontWeight: FontWeight.w600,
        ),
        border: fieldBorder(p.ink),
        enabledBorder: fieldBorder(p.ink),
        focusedBorder: fieldBorder(p.ink),
        disabledBorder: fieldBorder(p.muted),
        errorBorder: fieldBorder(p.ink),
        focusedErrorBorder: fieldBorder(p.ink),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: primary,
        disabledColor: p.line,
        labelStyle: AppText.buttonLabel.copyWith(fontSize: 12, color: p.ink),
        side: side,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        // The toast stays dark-on-light in both themes: it is a thing
        // that arrives over the page, not part of it.
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.ink,
        contentTextStyle: AppText.body.copyWith(
          color: isDark ? AppColors.inkDark : AppColors.surface,
        ),
        actionTextColor: AppColors.sun,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rowAll),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        elevation: 0,
        titleTextStyle: AppText.cardTitle.copyWith(color: p.ink),
        contentTextStyle: AppText.body.copyWith(color: p.ink),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: side,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.card),
          ),
          side: side,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        elevation: 0,
        textStyle: AppText.body.copyWith(color: p.ink),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.rowAll,
          side: side,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.ink,
        textColor: p.ink,
        titleTextStyle: AppText.body.copyWith(color: p.ink),
        subtitleTextStyle: AppText.caption.copyWith(color: p.subtle),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(p.surface),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.leaf : p.line,
        ),
        trackOutlineColor: WidgetStatePropertyAll(p.ink),
        trackOutlineWidth: const WidgetStatePropertyAll(AppBorders.width),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.leaf
              : p.surface,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.ink),
        side: side,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.ink : p.muted,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.ink,
        linearTrackColor: p.line,
        circularTrackColor: p.line,
        linearMinHeight: 12,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: AppColors.ink,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: side,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.ink,
        selectionColor: p.brandTint,
        selectionHandleColor: p.ink,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.ink,
          borderRadius: AppRadius.controlAll,
        ),
        textStyle: AppText.caption.copyWith(color: p.canvas),
      ),
    );
  }
}
