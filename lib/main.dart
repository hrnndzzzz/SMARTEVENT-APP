import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/welcome_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/adviser_dashboard_screen.dart';
import 'screens/search_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/risk_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/income_screen.dart';
import 'screens/receipts_screen.dart';
import 'screens/events_screen.dart';
import 'screens/proposal_letters_screen.dart';
import 'widgets/circle_menu.dart';

void main() {
  runApp(const SmartEventApp());
}

class SmartEventApp extends StatelessWidget {
  const SmartEventApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // Kick off the stored-session check as soon as the state exists, so
      // the gate below has something to wait for.
      create: (_) => AppState()..restoreSession(),
      child: MaterialApp(
        title: 'SmartEvent',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _StartupGate(),
      ),
    );
  }
}

/// Decides the first screen once the stored-token check has finished:
/// straight into the app for a session that is still valid, otherwise the
/// welcome flow. Without this, a securely stored token would never be used.
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (!app.sessionChecked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Checked before the role, not after: an account that still owes a
    // password change has no readable profile, so its role is null even
    // though it is signed in. Testing the role first would send it back to
    // the welcome screen in a loop.
    if (app.mustSetPassword) {
      return const ChangePasswordScreen(mandatory: true);
    }

    final role = app.currentRole;
    if (role == null) return const WelcomeScreen();

    return RootShell(role: role);
  }
}

class RootShell extends StatefulWidget {
  final UserRole role;
  const RootShell({super.key, this.role = UserRole.officer});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  /// The landing screen for each role.
  ///
  /// Treasurer shares the operational dashboard with Officer for now; the
  /// difference between them is which write controls appear, which each
  /// screen decides from the role's capabilities rather than from which
  /// dashboard it is. SDS Staff never reaches an operational dashboard.
  Widget get _home => switch (widget.role) {
        UserRole.admin || UserRole.superAdmin => const AdminDashboardScreen(),
        UserRole.adviser => const AdviserDashboardScreen(),
        UserRole.treasurer || UserRole.officer => const DashboardScreen(),
        UserRole.sdsStaff => const ProposalLettersScreen(),
      };

  Map<int, Widget> get _screens => {
    0: _home,
    1: const SearchScreen(),
    2: const ScannerScreen(),
    3: const RiskScreen(),
    4: const InventoryScreen(),
    5: const EventsScreen(),
    6: const CategoriesScreen(),
    7: const ReceiptsScreen(),
    8: const IncomeScreen(),
  };

  /// Navigation offered to this role.
  ///
  /// SDS Staff is isolated to proposal letters — no dashboard, events,
  /// finance, inventory or reports. Scanner captures receipts, which is a
  /// finance write, so only roles that can record finance are offered it;
  /// Officers and Advisers reach the rest read-only.
  List<CircleMenuItem> _menuItems() {
    if (widget.role.isLetterOnly) {
      return [
        CircleMenuItem(
          icon: Icons.description_outlined,
          label: 'Letters',
          onTap: () => _goTo(0),
        ),
      ];
    }

    return [
      CircleMenuItem(icon: Icons.grid_view_outlined, label: 'Dashboard', onTap: () => _goTo(0)),
      CircleMenuItem(icon: Icons.search, label: 'Search', onTap: () => _goTo(1)),
      if (widget.role.canRecordFinance)
        CircleMenuItem(icon: Icons.document_scanner_outlined, label: 'Scanner', onTap: () => _goTo(2)),
      CircleMenuItem(icon: Icons.warning_amber_outlined, label: 'Risk', onTap: () => _goTo(3)),
      CircleMenuItem(icon: Icons.inventory_2_outlined, label: 'Inventory', onTap: () => _goTo(4)),
      CircleMenuItem(icon: Icons.event_outlined, label: 'Events', onTap: () => _goTo(5)),
      // Every operational role reads categories; only Admin/Super Admin
      // sees the write controls once inside.
      CircleMenuItem(icon: Icons.folder_outlined, label: 'Categories', onTap: () => _goTo(6)),
      // Everyone operational can read receipts; only reviewers see the
      // decision controls once inside one.
      CircleMenuItem(icon: Icons.receipt_outlined, label: 'Receipts', onTap: () => _goTo(7)),
      CircleMenuItem(icon: Icons.savings_outlined, label: 'Income', onTap: () => _goTo(8)),
    ];
  }

  void _goTo(int i) {
    if (_screens.containsKey(i)) setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AppState>().themeColor;

    return Scaffold(
      body: Stack(
        children: [
          // SDS Staff has exactly one destination, so index 0 is always its
          // letters screen and the operational screens stay unreachable.
          widget.role.isLetterOnly ? _home : (_screens[_index] ?? _home),
          CircleMenu(
            color: themeColor,
            items: _menuItems(),
          ),
        ],
      ),
    );
  }
}