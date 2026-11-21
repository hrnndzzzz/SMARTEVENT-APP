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
import 'package:smartevent/screens/menu_panel.dart';
import 'package:smartevent/screens/money_screen.dart';
import 'package:smartevent/screens/home_screen.dart';
import 'package:smartevent/screens/events_hub_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/widgets/brand_pill.dart';
import 'package:smartevent/widgets/connection_banner.dart';
import 'package:smartevent/theme/app_colors.dart';
import 'package:smartevent/theme/app_theme.dart';

Future<void> font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

/// The icons, from the SDK's own cache.
///
/// FLUTTER_ROOT rather than the running binary's path: flutter_tester
/// lives three levels inside bin/cache, and walking up from it landed
/// one directory short — which failed silently and rendered another
/// page of hollow squares.
///
/// flutter_test ships no icon font, so every `Icon` in a golden came
/// out as a hollow square — which is fine for measuring a layout and
/// useless for looking at one. Located rather than hardcoded: the path
/// carries whoever's machine the SDK lives on.
Future<void> icons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final file = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!file.existsSync()) return;
  await font('MaterialIcons', [file.path]);
}

void main() {
  testWidgets('money', (tester) async {
    await font('Lexend', ['fonts/Lexend-Regular.ttf', 'fonts/Lexend-Medium.ttf',
      'fonts/Lexend-Bold.ttf', 'fonts/Lexend-ExtraBold.ttf']);
    await font('IBMPlexMono',
        ['fonts/IBMPlexMono-Regular.ttf', 'fonts/IBMPlexMono-Medium.ttf']);
    await icons();
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
    await font('Lexend', ['fonts/Lexend-Regular.ttf', 'fonts/Lexend-Medium.ttf',
      'fonts/Lexend-Bold.ttf', 'fonts/Lexend-ExtraBold.ttf']);
    await font('IBMPlexMono',
        ['fonts/IBMPlexMono-Regular.ttf', 'fonts/IBMPlexMono-Medium.ttf']);
    await icons();
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
    await font('Lexend', ['fonts/Lexend-Regular.ttf', 'fonts/Lexend-Medium.ttf',
      'fonts/Lexend-Bold.ttf', 'fonts/Lexend-ExtraBold.ttf']);
    await font('IBMPlexMono',
        ['fonts/IBMPlexMono-Regular.ttf', 'fonts/IBMPlexMono-Medium.ttf']);
    await icons();
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
    await font('Lexend', ['fonts/Lexend-Regular.ttf', 'fonts/Lexend-Medium.ttf',
      'fonts/Lexend-Bold.ttf', 'fonts/Lexend-ExtraBold.ttf']);
    await font('IBMPlexMono',
        ['fonts/IBMPlexMono-Regular.ttf', 'fonts/IBMPlexMono-Medium.ttf']);
    await icons();
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

  testWidgets('inventory-dark', (tester) async {
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
        theme: AppTheme.dark(accent: app.themeColor),
        home: const InventoryScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(InventoryScreen), matchesGoldenFile('goldens/inventory-dark.png'));
  });

  testWidgets('events-dark', (tester) async {
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
        theme: AppTheme.dark(accent: app.themeColor),
        home: const EventsScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(EventsScreen), matchesGoldenFile('goldens/events-dark.png'));
  });

  testWidgets('admin-dark', (tester) async {
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
        theme: AppTheme.dark(accent: app.themeColor),
        home: const AdminScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(AdminScreen), matchesGoldenFile('goldens/admin-dark.png'));
  });

  testWidgets('home', (tester) async {
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
        home: const HomeScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(HomeScreen), matchesGoldenFile('goldens/home.png'));
  });

  testWidgets('events-hub', (tester) async {
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
        home: const EventsHubScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
        find.byType(EventsHubScreen), matchesGoldenFile('goldens/events-hub.png'));
  });

  testWidgets('menu', (tester) async {
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
        home: const MenuPanel(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
        find.byType(MenuPanel), matchesGoldenFile('goldens/menu.png'));
  });

  // The menu on the navy, which is the one screen carrying all seven
  // module colours at once — and so the only place the dark palette can
  // be judged as a set rather than one block at a time.
  testWidgets('menu-dark', (tester) async {
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
        home: const MenuPanel(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
        find.byType(MenuPanel), matchesGoldenFile('goldens/menu-dark.png'));
  });

  // The dashboard on the navy: the status tones, which are the other
  // half of the palette, all on one screen.
  testWidgets('home-dark', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(822, 1900);
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
        home: const HomeScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
        find.byType(HomeScreen), matchesGoldenFile('goldens/home-dark.png'));
  });

  // The header saying what happened to the connection, in each of the
  // three states it can be in. Driven by real transitions rather than
  // by setting a flag, because the announcement only fires on a change.
  for (final (name, offline) in [('offline', true), ('online', false)]) {
    testWidgets('brand-pill-$name', (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(822, 240);
      addTearDown(tester.view.reset);
      // Always online first: an announcement is a change, and the
      // state it starts in is not one.
      final reach = Reachability()..report(reachable: true);

      await tester.pumpWidget(MaterialApp(
        // CITE's accent, not the default. A pill rendered on the
        // fallback is a picture of a department nobody is signed in to,
        // and the whole point of this one is the colour.
        theme: AppTheme.light(accent: AppColors.orange),
        home: ChangeNotifierProvider<Reachability>.value(
          value: reach,
          child: ConnectionBanner(
            child: Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: const [BrandPill(), Spacer()]),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      reach.report(reachable: false);
      if (!offline) {
        // Away and back, so this is a recovery rather than a first
        // answer — which is not news and says nothing. The hold on the
        // "No connection" is run out first, or the two would overlap.
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        reach.report(reachable: true);
      }
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      await expectLater(
          find.byType(BrandPill), matchesGoldenFile('goldens/brand-pill-$name.png'));

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      reach.dispose();
    });
  }
}
