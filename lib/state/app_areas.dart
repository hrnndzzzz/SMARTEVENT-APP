import 'package:flutter/material.dart';

import '../screens/admin_screen.dart';
import '../screens/events_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/money_screen.dart';
import '../screens/proposal_letters_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/risk_screen.dart';
import '../screens/search_screen.dart';
import '../theme/brut.dart';
import 'app_state.dart';

/// The app's areas, in one list.
///
/// Before this there were two navigation systems — a six-tab bar and a
/// radial menu — and the menu repeated every tab before adding five more.
/// Eleven destinations, no grouping, and the same thing reachable two
/// ways. That is what made the app feel like a pile.
///
/// Now there is one list. The home screen renders it as cards, the side
/// rail and the bottom bar render the first few as icons, and all three
/// read from here, so they cannot drift apart.
class AppArea {
  const AppArea({
    required this.id,
    required this.title,
    required this.blurb,
    required this.icon,
    required this.tone,
    required this.builder,
    this.badge,
    this.visibleTo,
  });

  final String id;
  final String title;

  /// One line, shown when the card has room and in the peek.
  final String blurb;
  final IconData icon;
  final BrutTone tone;
  final WidgetBuilder builder;

  /// The number on the card. Null means this area does not count
  /// anything — better than showing a zero that means "not loaded".
  final int Function(AppState app)? badge;

  /// Null means everyone who can sign in.
  final bool Function(UserRole role)? visibleTo;

  bool isVisibleTo(UserRole? role) =>
      role != null && (visibleTo == null || visibleTo!(role));
}

/// Every area, in the order they appear on the home grid.
const List<AppArea> appAreas = [
  AppArea(
    id: 'events',
    title: 'Events',
    blurb: 'Proposals, approvals and budgets',
    icon: Icons.event_outlined,
    tone: BrutTone.brand,
    badge: _pendingEvents,
    builder: _events,
  ),
  AppArea(
    id: 'money',
    title: 'Money',
    blurb: 'Receipts, expenses, income and budgets',
    icon: Icons.payments_outlined,
    tone: BrutTone.orange,
    badge: _pendingExpenses,
    builder: _money,
  ),
  AppArea(
    id: 'inventory',
    title: 'Inventory',
    blurb: 'Stock, movements and low-stock items',
    icon: Icons.inventory_2_outlined,
    tone: BrutTone.mint,
    badge: _lowStock,
    builder: _inventory,
  ),
  AppArea(
    id: 'reports',
    title: 'Reports',
    blurb: 'Financial reports and exports',
    icon: Icons.insert_chart_outlined,
    tone: BrutTone.violet,
    builder: _reports,
  ),
  AppArea(
    id: 'risk',
    title: 'Flagged',
    blurb: 'Expenses worth a second look',
    icon: Icons.flag_outlined,
    tone: BrutTone.sun,
    badge: _flagged,
    builder: _risk,
  ),
  AppArea(
    id: 'letters',
    title: 'Letters',
    blurb: 'Proposal letters for events',
    icon: Icons.description_outlined,
    tone: BrutTone.teal,
    badge: _letters,
    builder: _lettersScreen,
  ),
  AppArea(
    id: 'search',
    title: 'Search',
    blurb: 'Find an event or a transaction',
    icon: Icons.search,
    tone: BrutTone.neutral,
    builder: _search,
  ),
  AppArea(
    id: 'admin',
    title: 'Administration',
    blurb: 'Roster, accounts and the audit log',
    icon: Icons.manage_accounts_outlined,
    tone: BrutTone.brand,
    visibleTo: _canAdminister,
    builder: _admin,
  ),
];

List<AppArea> areasFor(UserRole? role) => [
  for (final area in appAreas)
    if (area.isVisibleTo(role)) area,
];

/// What belongs on the menu panel.
///
/// Dashboard and Events are left out: they are the screens either side of
/// the menu, and an entry that goes where a swipe already goes is the
/// duplication that made the old navigation a pile.
List<AppArea> menuAreasFor(UserRole? role) => [
  for (final area in areasFor(role))
    if (area.id != 'events') area,
];

AppArea? areaById(String id) => appAreas.where((a) => a.id == id).firstOrNull;

// Top-level functions, because a const list cannot hold a closure.
int _pendingEvents(AppState app) =>
    app.events.where((e) => e.status.isPending).length;
int _pendingExpenses(AppState app) => app.pendingExpenses.length;
int _lowStock(AppState app) => app.catalog.where((i) => i.isLowStock).length;
int _flagged(AppState app) => app.flaggedExpenses.length;
int _letters(AppState app) => app.letters.length;

bool _canAdminister(UserRole role) => role.canManageMembers;

Widget _events(BuildContext _) => const EventsScreen();
Widget _money(BuildContext _) => const MoneyScreen();
Widget _inventory(BuildContext _) => const InventoryScreen();
Widget _reports(BuildContext _) => const ReportsScreen();
Widget _risk(BuildContext _) => const RiskScreen();
Widget _lettersScreen(BuildContext _) => const ProposalLettersScreen();
Widget _search(BuildContext _) => const SearchScreen();
Widget _admin(BuildContext _) => const AdminScreen();
