import 'package:flutter/material.dart';

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
/// screens. So a module never wears them. The module colours are
/// saturated and carry a band; the status colours are lighter and carry
/// a chip. That difference in weight is as much of the separation as
/// the hue is — you can tell a band from a chip without knowing either
/// colour.
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
    Module.reports => 'Financial reports',
    Module.flagged => 'Flagged for review',
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
  /// module whose colour was already decided outside this file.
  Color get color => switch (this) {
    Module.events => const Color(0xFF2E6F9E),
    Module.money => const Color(0xFFF26B21),
    Module.inventory => const Color(0xFF6F4E8E),
    Module.reports => const Color(0xFFB5791F),
    Module.flagged => const Color(0xFFA8322A),
    Module.admin => const Color(0xFF3F6B4F),
    Module.search => const Color(0xFF5B5750),
  };

  /// On the navy. The dark canvas is a colour rather than a grey, so a
  /// band has to clear it rather than merely be darker than white —
  /// Events' steel blue sat on the navy and all but vanished.
  Color get colorDark => switch (this) {
    Module.events => const Color(0xFF4E95C8),
    Module.money => const Color(0xFFF2823F),
    Module.inventory => const Color(0xFF8E6BB0),
    Module.reports => const Color(0xFFD19A3C),
    Module.flagged => const Color(0xFFC9534A),
    Module.admin => const Color(0xFF5C9070),
    Module.search => const Color(0xFF8A857C),
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
