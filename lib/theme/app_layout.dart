import 'package:flutter/widgets.dart';

/// The measurements the whole app lays out on, in logical pixels at a
/// 390 × 844 phone.
///
/// They exist so screens stop choosing their own. Before this there were
/// twelve different combinations of screen padding in the app, which is
/// the kind of thing nobody notices one screen at a time and everybody
/// notices flipping between them.
class AppLayout {
  AppLayout._();

  // ── The frame ─────────────────────────────────────────────────────────
  /// Left and right on every screen. The only exception is sign-in, which
  /// is a single centred column and breathes at 20.
  static const double gutter = 16;

  /// Top and bottom inside the scrolling area.
  static const double contentPadding = 16;

  /// The app never gets wider than a phone, however wide the window is.
  static const double columnMaxWidth = 420;

  // ── Gaps ──────────────────────────────────────────────────────────────
  /// Between related items — chips, badges, a label and its field.
  static const double tight = 8;

  /// Between cards.
  static const double between = 12;

  /// Between sections.
  static const double section = 20;

  /// A phone short enough that the extra 2px per card matters.
  static const double shortScreenHeight = 780;

  /// [between], tightened on a short phone so a screen that just fits
  /// still just fits.
  static double cardGap(BuildContext context) =>
      MediaQuery.sizeOf(context).height <= shortScreenHeight ? 10 : between;

  // ── Controls ──────────────────────────────────────────────────────────
  /// Back buttons and the icon buttons beside a title.
  static const double iconButton = 40;

  /// A primary action in a footer, and the square back button beside it.
  static const double footerAction = 52;

  /// Buttons inside cards and rows.
  static const double smallAction = 36;

  /// The avatar in a header, and the icon tile on a category card.
  static const double avatar = 38;

  // ── Headers and footers ───────────────────────────────────────────────
  static const double headerTopPadding = 10;
  static const double headerBottomPadding = 12;
  static const double footerTopPadding = 12;

  /// The minimum bottom padding in a footer; the phone's safe area wins
  /// when it is larger.
  static const double footerBottomPadding = 12;

  /// Step bars under a flow header.
  static const double stepBarHeight = 8;
  static const double stepBarGap = 6;
  static const double stepBarTopGap = 12;

  // ── Sheets ────────────────────────────────────────────────────────────
  /// A sheet never takes more than this much of the screen. One that
  /// fills it is a screen, and should have been one.
  static const double sheetMaxHeightFraction = 0.85;
  static const double sheetSidePadding = 16;
  static const double sheetVerticalPadding = 12;

  // ── Popovers ──────────────────────────────────────────────────────────
  /// Only a fallback now: a popover hangs off the control that opened
  /// it, and uses this corner only when that control cannot be measured.
  static const double popoverTop = 58;
  static const double popoverMargin = 16;
  static const double popoverMaxWidth = 330;

  /// Between a control and the panel it opens. Close enough to read as
  /// attached to it, clear enough not to touch.
  static const double popoverGap = 8;
}
