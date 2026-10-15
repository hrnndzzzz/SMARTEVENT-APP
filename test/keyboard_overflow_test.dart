import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/admin_screen.dart';
import 'package:smartevent/screens/categories_screen.dart';
import 'package:smartevent/screens/create_event_screen.dart';
import 'package:smartevent/screens/income_screen.dart';
import 'package:smartevent/screens/inventory_screen.dart';
import 'package:smartevent/screens/proposal_letters_screen.dart';
import 'package:smartevent/screens/search_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

Widget _host(Widget child, double keyboard, UserRole role) {
  final app = AppState()..devQuickLogin(role);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
        child: w!,
      ),
      home: child,
    ),
  );
}

void main() {
  final screens = <String, Widget>{
    'create event': const CreateEventScreen(),
    'categories': const CategoriesScreen(),
    'proposal letters': const ProposalLettersScreen(),
    'income': const IncomeScreen(),
    'admin': const AdminScreen(),
    'search': const SearchScreen(),
    'inventory': const InventoryScreen(),
  };

  // Every screen that lays itself out instead of scrolling has to survive
  // the keyboard taking half the window. The budget step did not: it
  // carried a fixed keypad under a fixed field, and overflowed by 153px
  // on a real phone.
  for (final entry in screens.entries) {
    testWidgets('${entry.key} survives the keyboard', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(entry.value, 0, UserRole.superAdmin));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.takeException(),
        isNull,
        reason: '${entry.key}, no keyboard',
      );

      await tester.pumpWidget(_host(entry.value, 320, UserRole.superAdmin));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.takeException(),
        isNull,
        reason: '${entry.key}, keyboard up',
      );
    });
  }
}
