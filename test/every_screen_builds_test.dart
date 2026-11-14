import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/about_screen.dart';
import 'package:smartevent/screens/admin_screen.dart';
import 'package:smartevent/screens/categories_screen.dart';
import 'package:smartevent/screens/events_screen.dart';
import 'package:smartevent/screens/expenses_screen.dart';
import 'package:smartevent/screens/home_screen.dart';
import 'package:smartevent/screens/income_screen.dart';
import 'package:smartevent/screens/inventory_screen.dart';
import 'package:smartevent/screens/money_screen.dart';
import 'package:smartevent/screens/proposal_letters_screen.dart';
import 'package:smartevent/screens/receipts_screen.dart';
import 'package:smartevent/screens/reports_screen.dart';
import 'package:smartevent/screens/risk_screen.dart';
import 'package:smartevent/screens/search_screen.dart';
import 'package:smartevent/screens/settings_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/state/sfx.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Every screen, built at a real phone size, in both themes.
///
/// A widget test fails on a RenderFlex overflow, so this is a sweep for
/// clipping rather than a test of behaviour. It exists because the type
/// changed: IBM Plex Mono runs about 15% wider than Lexend, and the
/// first screen anyone looked at had lost a filter chip off its right
/// edge. Checking sixteen screens by eye, twice, is how that gets
/// missed.
void main() {
  final screens = <String, Widget>{
    'dashboard': const HomeScreen(),
    'money': const MoneyScreen(),
    'events': const EventsScreen(),
    'inventory': const InventoryScreen(),
    'reports': const ReportsScreen(),
    'flagged': const RiskScreen(),
    'admin': const AdminScreen(),
    'settings': const SettingsScreen(),
    'about': const AboutScreen(),
    'expenses': const ExpensesScreen(),
    'receipts': const ReceiptsScreen(),
    'income': const IncomeScreen(),
    'categories': const CategoriesScreen(),
    'search': const SearchScreen(),
    'letters': const ProposalLettersScreen(),
  };

  // The narrow end of what this app actually meets. A phone that fits
  // nothing is not a design constraint, but 360dp is a real Android.
  const sizes = <String, Size>{
    '360x800': Size(360, 800),
    '411x890': Size(411, 890),
  };

  for (final theme in ['light', 'dark']) {
    for (final size in sizes.entries) {
      for (final screen in screens.entries) {
        testWidgets('${screen.key} builds — $theme ${size.key}', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size.value;
          addTearDown(tester.view.reset);

          final app = AppState()..enterDemo(role: UserRole.superAdmin);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<AppState>.value(value: app),
                ChangeNotifierProvider(create: (_) => AppSettings()),
                ChangeNotifierProvider(create: (_) => Reachability()),
                ChangeNotifierProvider(create: (_) => NoticeShelf()),
                ChangeNotifierProvider(create: (_) => SfxPlayer()),
              ],
              child: MaterialApp(
                theme: theme == 'light'
                    ? AppTheme.light(accent: app.themeColor)
                    : AppTheme.dark(accent: app.themeColor),
                home: screen.value,
              ),
            ),
          );
          // Not pumpAndSettle: the notification bell animates forever
          // while anything is unread.
          await tester.pump(const Duration(milliseconds: 400));

          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
