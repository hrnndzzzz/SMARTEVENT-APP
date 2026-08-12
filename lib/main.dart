import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/search_screen.dart';
import 'screens/inventory_screen.dart';
import 'widgets/docket_nav_bar.dart';

void main() {
  runApp(const SmartEventApp());
}

class SmartEventApp extends StatelessWidget {
  const SmartEventApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartEvent',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const RootShell(),
    );
  }
}

/// Holds the current tab and swaps between screens, sharing one nav bar.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  // Only Dashboard, Search, and Inventory are built so far.
  // Tapping Scanner or Risk (indexes 2, 3) does nothing yet.
  static const _screens = [
    DashboardScreen(),
    SearchScreen(),
    InventoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final screenIndex = _index > 2 ? 0 : _index; // safety fallback
    return Scaffold(
      body: _screens[screenIndex],
      bottomNavigationBar: DocketNavBar(
        activeIndex: _index,
        onTap: (i) {
          if (i <= 2) setState(() => _index = i); // only wired tabs switch
        },
      ),
    );
  }
}