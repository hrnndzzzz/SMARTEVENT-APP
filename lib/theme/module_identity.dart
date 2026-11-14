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

  /// Money keeps the department's orange — it is the one module whose
  /// colour was already decided by something outside this file.
  Color get color => switch (this) {
    Module.events => const Color(0xFF2E6F9E),
    Module.money => const Color(0xFFF26B21),
    Module.inventory => const Color(0xFF6F4E8E),
    Module.reports => const Color(0xFFB5791F),
    Module.flagged => const Color(0xFFA8322A),
    Module.admin => const Color(0xFF3F6B4F),
    Module.search => const Color(0xFF5B5750),
  };
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
