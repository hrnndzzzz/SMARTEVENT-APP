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
/// On the cream the field is the darker of the two; on the navy it is
/// the dimmer one, and the chip is what stands off the page. Both ways
/// round the band recedes and the chip does not, which is the thing
/// that has to stay true.
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

  /// On the cream. Money keeps the department's orange — it is the one
  /// module whose colour was already decided outside this file, so it is
  /// [AppColors.orange] itself rather than a copy of its hex, and comes
  /// down with it when the orange does.
  Color get color => switch (this) {
    Module.events => const Color(0xFF2E6F9E),
    Module.money => AppColors.orange,
    Module.inventory => const Color(0xFF6F4E8E),
    Module.reports => const Color(0xFFB5791F),
    Module.flagged => const Color(0xFFA8322A),
    Module.admin => const Color(0xFF3F6B4F),
    Module.search => const Color(0xFF5B5750),
  };

  /// On the navy: [color] run through [AppColors.onDarkCanvas] at
  /// [AppColors.darkBandLuminance], which is the whole of the rule.
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
    Module.inventory => const Color(0xFF7F5AA3),
    Module.reports => const Color(0xFF88642D),
    Module.flagged => const Color(0xFFB6443D),
    Module.admin => const Color(0xFF457556),
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
