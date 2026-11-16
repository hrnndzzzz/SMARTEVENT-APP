import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Which part of the app you are in, and what that looks like.
///
/// One list, read by the module band at the top of a screen and by the
/// menu that offers them, so the two cannot disagree about what colour
/// Reports is.
///
/// ## Why these are not the status colours
///
/// Green, yellow and coral mean approved, waiting and returned, and
/// they have to keep meaning that on a chip sitting inside one of these
/// screens. So a module never wears them.
///
/// The hue is only half of the separation. The other half is weight: a
/// module is a large, quiet field and a status is a small, bright mark,
/// so you can tell a band from a chip without knowing either colour.
/// The band recedes and the chip does not, on the cream and on the navy
/// alike — which is the thing that has to stay true, and is now a
/// number rather than a habit. Every colour below is under
/// [AppColors.bandLuminance] and every accent is over 0.22, so the
/// seven bands carry one ink and the chips sitting on them carry the
/// other.
enum Module {
  events,
  money,
  inventory,
  reports,
  flagged,
  admin,
  search;

  String get title => switch (this) {
    Module.events => 'Events',
    Module.money => 'Money',
    Module.inventory => 'Inventory',
    // Analytics, since the module became that: KPIs, insights, five
    // charts and a ledger, with the reports as one thing it can hand
    // you rather than the whole of it. It also fits a 360pt band,
    // which 'Financial reports' did not.
    Module.reports => 'Analytics',
    // 'Flagged for review' was the only title that would not fit its
    // band on one line, and the menu had always called it this.
    Module.flagged => 'Flagged',
    Module.admin => 'Administration',
    Module.search => 'Search',
  };

  IconData get icon => switch (this) {
    Module.events => Icons.event_outlined,
    Module.money => Icons.account_balance_wallet_outlined,
    Module.inventory => Icons.warehouse_outlined,
    Module.reports => Icons.insights_outlined,
    Module.flagged => Icons.outlined_flag,
    Module.admin => Icons.manage_accounts_outlined,
    Module.search => Icons.search,
  };

  /// On the cream: every one of them [AppColors.bandOnCream] of itself,
  /// which is to say under [AppColors.bandLuminance] and carrying light
  /// ink. Five already were. Two were not:
  ///
  /// * **Money** was [AppColors.orange] itself — the department's own
  ///   colour, the one value here that was decided outside this file —
  ///   at 0.28, the brightest field in the app. It is that orange still,
  ///   to the degree and to the percent, held down to the band. The
  ///   bright one has not gone anywhere: it is what the department pill,
  ///   the avatar and the peso figure are, and those are chips.
  /// * **Analytics** was a gold at 0.24, and the same hue deepened.
  ///
  /// So a menu of seven blocks prints seven titles in one colour, where
  /// it used to print five light and two dark. The dashboard had the
  /// same fault in a smaller place — four tiles whose icon blocks take
  /// [color], two of them Money's.
  /// Two hues, not seven. SmartEvent is blue and orange — CITE's two
  /// and the logo's two — and the set had drifted to a purple
  /// Inventory at 271° and a green Admin at 142°, which belong to
  /// neither. They are blue now, spread across the family rather than
  /// stacked on it: Events 205°, Inventory 218°, Admin 234°. Money and
  /// Analytics are the orange side at 21° and 36°.
  ///
  /// Two exceptions, and only two. Flagged keeps its red because that
  /// is a status, not an identity — the same red that marks a rejected
  /// proposal. Search is a near-grey at 0.06 saturation, which is the
  /// absence of a hue rather than a seventh one.
  ///
  /// All three blues carry Events' saturation (0.549) as well as the
  /// band's luminance, because equal luminance alone still let a
  /// vivid block sit beside a muted one and read as louder.
  Color get color => switch (this) {
    Module.events => const Color(0xFF2E6F9E),
    Module.money => const Color(0xFFAE4E19),
    Module.inventory => const Color(0xFF3768BD),
    Module.reports => const Color(0xFF906019),
    Module.flagged => const Color(0xFFA8322A),
    Module.admin => const Color(0xFF535FCD),
    Module.search => const Color(0xFF5B5750),
  };

  /// On the navy: [color] run through [AppColors.onDarkCanvas] at
  /// [AppColors.bandLuminance], which is the whole of the rule.
  ///
  /// These are the largest areas of colour in the app — a band is the
  /// full width of the screen and a menu block is a quarter of it — so
  /// they go *below* `foregroundOn`'s threshold and carry light ink,
  /// rather than above it like the chips and badges do. That is the
  /// opposite of what they used to do, and the reason is what the dark
  /// menu looked like: Money and Analytics were the two brightest
  /// things on the screen, brighter than any text on it, while
  /// Inventory and Flagged sat below the line — so four blocks in one
  /// grid printed their titles in two different colours.
  ///
  /// Written out rather than computed, because a band is rebuilt on
  /// every frame of a scroll and these never change.
  Color get colorDark => switch (this) {
    Module.events => const Color(0xFF346F9B),
    Module.money => const Color(0xFF9D5934),
    Module.inventory => const Color(0xFF3D69B7),
    Module.reports => const Color(0xFF88632D),
    Module.flagged => const Color(0xFFB6443D),
    Module.admin => const Color(0xFF5560C6),
    Module.search => const Color(0xFF6E6A61),
  };

  /// The one to use. Picks by the theme rather than by the caller, so a
  /// screen cannot ask for the light colour on a dark page.
  Color colorIn(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? colorDark : color;
}

/// The module an area belongs to, by the id [AppArea] already uses.
///
/// Returns null rather than guessing: an area this file has not heard
/// of gets the neutral treatment instead of borrowing someone's colour.
Module? moduleForAreaId(String id) => switch (id) {
  'events' => Module.events,
  'money' => Module.money,
  'inventory' => Module.inventory,
  'reports' => Module.reports,
  'risk' => Module.flagged,
  'admin' => Module.admin,
  'search' => Module.search,
  _ => null,
};
