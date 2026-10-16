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
/// ## The two colours, and the three
///
/// An area is orange when it is about money — Money, Reports, Flagged —
/// and blue when it is not. That is the whole rule, and it is why the
/// menu now reads as one system rather than a row of unrelated tiles:
/// the department is orange and blue, so the app is.
///
/// Green, yellow and coral never fill an area. They mean approved,
/// waiting and returned, and a screen that spends them on a menu entry
/// has nothing left to say with them where it matters.
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
    tone: BrutTone.brand,
    badge: _lowStock,
    builder: _inventory,
  ),
  AppArea(
    id: 'reports',
    title: 'Reports',
    blurb: 'Financial reports and exports',
    icon: Icons.insert_chart_outlined,
    tone: BrutTone.orange,
    builder: _reports,
  ),
  AppArea(
    id: 'risk',
    title: 'Flagged',
    blurb: 'Expenses worth a second look',
    icon: Icons.flag_outlined,
    tone: BrutTone.orange,
    badge: _flagged,
    builder: _risk,
  ),
  AppArea(
    id: 'letters',
    title: 'Letters',
    blurb: 'Proposal letters for events',
    icon: Icons.description_outlined,
    tone: BrutTone.brand,
    badge: _letters,
    // Officers reach none of it, and sign-in does not even load the
    // list for them — so the card would open on an empty screen that
    // will never fill.
    visibleTo: _canReadLetters,
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
  // Every area is operational, so a role the backend keeps out of
  // operational data — SDS Staff, a signatory — is offered none of them
  // rather than a grid of screens that would all come back 403.
  if (role?.hasOperationalAccess ?? false)
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

bool _canReadLetters(UserRole role) => role.canAccessProposalLetters;

Widget _events(BuildContext _) => const EventsScreen();
Widget _money(BuildContext _) => const MoneyScreen();
Widget _inventory(BuildContext _) => const InventoryScreen();
Widget _reports(BuildContext _) => const ReportsScreen();
Widget _risk(BuildContext _) => const RiskScreen();
Widget _lettersScreen(BuildContext _) => const ProposalLettersScreen();
Widget _search(BuildContext _) => const SearchScreen();
Widget _admin(BuildContext _) => const AdminScreen();
