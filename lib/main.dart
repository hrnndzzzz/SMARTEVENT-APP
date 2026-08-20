import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/welcome_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/search_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/risk_screen.dart';
import 'screens/inventory_screen.dart';
import 'widgets/docket_nav_bar.dart';

void main() {
  runApp(const SmartEventApp());
}

enum UserRole { officer, adviser, admin }

class SmartEventApp extends StatelessWidget {
  const SmartEventApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartEvent',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const WelcomeScreen(),
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
    0: widget.role == UserRole.admin ? const AdminDashboardScreen() : const DashboardScreen(),
    1: const SearchScreen(),
    2: const ScannerScreen(),
    3: const RiskScreen(),
    4: const InventoryScreen(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index] ?? const DashboardScreen(),
      bottomNavigationBar: DocketNavBar(
        activeIndex: _index,
        onTap: (i) {
          if (_screens.containsKey(i)) setState(() => _index = i);
        },
      ),
    );
  }
}