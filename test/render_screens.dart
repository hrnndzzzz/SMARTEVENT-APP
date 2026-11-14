// Not a test: a renderer.
//
// `flutter test` skips it — the filename does not end in _test.dart — so
// it only runs when asked:
//
//   flutter test --update-goldens test/render_screens.dart
//
// It writes test/goldens/*.png with the real fonts and the real theme,
// which is how a screen gets looked at without reinstalling the app on
// a phone that is carrying a differently-signed release build.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/events_screen.dart';
import 'package:smartevent/screens/reports_screen.dart';
import 'package:smartevent/screens/risk_screen.dart';
import 'package:smartevent/screens/expenses_screen.dart';
import 'package:smartevent/screens/receipts_screen.dart';
import 'package:smartevent/screens/income_screen.dart';
import 'package:smartevent/screens/admin_screen.dart';
import 'package:smartevent/screens/inventory_screen.dart';
import 'package:smartevent/screens/money_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

Future<void> font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

void main() {
  testWidgets('money', (tester) async {
    await font('Lexend', ['fonts/Lexend-Regular.ttf', 'fonts/Lexend-Medium.ttf']);
    await font('IBMPlexMono',
        ['fonts/IBMPlexMono-Regular.ttf', 'fonts/IBMPlexMono-Medium.ttf']);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(822, 1600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
        ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(accent: app.themeColor),
        home: const MoneyScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
        find.byType(MoneyScreen), matchesGoldenFile('goldens/money.png'));
  });

  testWidgets('inventory', (tester) async {
    await font('Lexend', ['fonts/Lexend-Regular.ttf', 'fonts/Lexend-Medium.ttf']);
    await font('IBMPlexMono',
        ['fonts/IBMPlexMono-Regular.ttf', 'fonts/IBMPlexMono-Medium.ttf']);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(822, 1600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
        ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(accent: app.themeColor),
        home: const InventoryScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(InventoryScreen),
        matchesGoldenFile('goldens/inventory.png'));
  });

  testWidgets('events', (tester) async {
    await font('Lexend', ['fonts/Lexend-Regular.ttf', 'fonts/Lexend-Medium.ttf']);
    await font('IBMPlexMono',
        ['fonts/IBMPlexMono-Regular.ttf', 'fonts/IBMPlexMono-Medium.ttf']);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(822, 1600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
        ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(accent: app.themeColor),
        home: const EventsScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
        find.byType(EventsScreen), matchesGoldenFile('goldens/events.png'));
  });

  testWidgets('money dark', (tester) async {
    await font('Lexend', ['fonts/Lexend-Regular.ttf', 'fonts/Lexend-Medium.ttf']);
    await font('IBMPlexMono',
        ['fonts/IBMPlexMono-Regular.ttf', 'fonts/IBMPlexMono-Medium.ttf']);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(822, 1600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
        ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(accent: app.themeColor),
        home: const MoneyScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MoneyScreen),
        matchesGoldenFile('goldens/money-dark.png'));
  });

  testWidgets('reports', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(822, 1600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo(role: UserRole.superAdmin);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
        ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(accent: app.themeColor),
        home: const ReportsScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(ReportsScreen), matchesGoldenFile('goldens/reports.png'));
  });

  testWidgets('flagged', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(822, 1600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo(role: UserRole.superAdmin);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
        ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(accent: app.themeColor),
        home: const RiskScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(RiskScreen), matchesGoldenFile('goldens/flagged.png'));
  });

  testWidgets('expenses', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(822, 1600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo(role: UserRole.superAdmin);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
        ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(accent: app.themeColor),
        home: const ExpensesScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(ExpensesScreen), matchesGoldenFile('goldens/expenses.png'));
  });

  testWidgets('receipts', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(822, 1600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo(role: UserRole.superAdmin);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
        ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(accent: app.themeColor),
        home: const ReceiptsScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(ReceiptsScreen), matchesGoldenFile('goldens/receipts.png'));
  });

  testWidgets('income', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(822, 1600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo(role: UserRole.superAdmin);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
        ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(accent: app.themeColor),
        home: const IncomeScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(IncomeScreen), matchesGoldenFile('goldens/income.png'));
  });

  testWidgets('admin', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(822, 1600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo(role: UserRole.superAdmin);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
        ChangeNotifierProvider(create: (_) => NoticeShelf()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(accent: app.themeColor),
        home: const AdminScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(AdminScreen), matchesGoldenFile('goldens/admin.png'));
  });
}
