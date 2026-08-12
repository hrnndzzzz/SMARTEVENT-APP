import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/search_screen.dart';
import 'screens/scanner_screen.dart';
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

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  // Keyed by nav bar position: 0=Dashboard, 1=Search, 2=Scanner,
  // 3=Risk (not built yet), 4=Inventory.
  static const Map<int, Widget> _screens = {
    0: DashboardScreen(),
    1: SearchScreen(),
    2: ScannerScreen(),
    4: InventoryScreen(),
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