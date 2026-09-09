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
import 'screens/events_screen.dart';
import 'widgets/circle_menu.dart';

void main() {
  runApp(const SmartEventApp());
}

class SmartEventApp extends StatelessWidget {
  const SmartEventApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'SmartEvent',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const WelcomeScreen(),
      ),
    );
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

  Map<int, Widget> get _screens => {
    0: switch (widget.role) {
      UserRole.admin => const AdminDashboardScreen(),
      UserRole.adviser => const AdviserDashboardScreen(),
      UserRole.officer => const DashboardScreen(),
    },
    1: const SearchScreen(),
    2: const ScannerScreen(),
    3: const RiskScreen(),
    4: const InventoryScreen(),
    5: const EventsScreen(),
  };

  void _goTo(int i) {
    if (_screens.containsKey(i)) setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AppState>().themeColor;

    return Scaffold(
      body: Stack(
        children: [
          _screens[_index] ?? const DashboardScreen(),
          CircleMenu(
            color: themeColor,
            items: [
              CircleMenuItem(icon: Icons.grid_view_outlined, label: 'Dashboard', onTap: () => _goTo(0)),
              CircleMenuItem(icon: Icons.search, label: 'Search', onTap: () => _goTo(1)),
              CircleMenuItem(icon: Icons.document_scanner_outlined, label: 'Scanner', onTap: () => _goTo(2)),
              CircleMenuItem(icon: Icons.warning_amber_outlined, label: 'Risk', onTap: () => _goTo(3)),
              CircleMenuItem(icon: Icons.inventory_2_outlined, label: 'Inventory', onTap: () => _goTo(4)),
              CircleMenuItem(icon: Icons.event_outlined, label: 'Events', onTap: () => _goTo(5)),
            ],
          ),
        ],
      ),
    );
  }
}