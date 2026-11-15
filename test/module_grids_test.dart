import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/screens/home_screen.dart';
import 'package:smartevent/screens/inventory_screen.dart';
import 'package:smartevent/screens/money_screen.dart';
import 'package:smartevent/screens/risk_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/widgets/stat_grid.dart';

/// The reviewer's two notes about the module screens: that they opened
/// on nothing, and that the dashboard did not say what the app is
/// about. Both are layout complaints with a measurable answer, so they
/// are measured here rather than looked at.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppState> open(
    WidgetTester tester,
    Widget screen, {
    UserRole role = UserRole.treasurer,
    Size size = const Size(420, 1400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppState()..enterDemo(role: role);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider(create: (_) => AppSettings()),
          ChangeNotifierProvider(create: (_) => Reachability()),
          ChangeNotifierProvider(create: (_) => NoticeShelf()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: screen),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return app;
  }

  group('StatGrid', () {
    testWidgets('four cells make two rows of two', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: StatGrid(
              cells: [
                StatCell(label: 'A', value: '1', tone: BrutTone.neutral),
                StatCell(label: 'B', value: '2', tone: BrutTone.neutral),
                StatCell(label: 'C', value: '3', tone: BrutTone.neutral),
                StatCell(label: 'D', value: '4', tone: BrutTone.neutral),
              ],
            ),
          ),
        ),
      );

      Rect cell(String label) =>
          tester.getRect(find.ancestor(
            of: find.text(label),
            matching: find.byType(BrutCard),
          ).first);

      // Two across: A and B share a top edge, C and D share theirs, and
      // the second row is below the first.
      expect(cell('A').top, cell('B').top);
      expect(cell('C').top, cell('D').top);
      expect(cell('C').top, greaterThan(cell('A').bottom));

      // Same size, all four. A grid whose cells differ by a few pixels
      // is the complaint that started this.
      final sizes = {
        for (final label in ['A', 'B', 'C', 'D']) cell(label).size,
      };
      expect(sizes, hasLength(1));
    });

    testWidgets('an odd cell leaves a hole, not a wide cell', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: StatGrid(
              cells: [
                StatCell(label: 'A', value: '1', tone: BrutTone.neutral),
                StatCell(label: 'B', value: '2', tone: BrutTone.neutral),
                StatCell(label: 'C', value: '3', tone: BrutTone.neutral),
              ],
            ),
          ),
        ),
      );

      Rect cell(String label) =>
          tester.getRect(find.ancestor(
            of: find.text(label),
            matching: find.byType(BrutCard),
          ).first);

      // A cell twice the width of its neighbours reads as the important
      // one when it is only the last one.
      expect(cell('C').width, cell('A').width);
    });
  });

  group('Money', () {
    testWidgets('the destinations are a 2x2, not five rows', (tester) async {
      await open(tester, const MoneyScreen());

      Rect square(String title) =>
          tester.getRect(find.ancestor(
            of: find.text(title),
            matching: find.byType(BrutCard),
          ).first);

      expect(square('Expenses').top, square('Receipts').top);
      expect(square('Income').top, square('Categories').top);
      expect(square('Income').top, greaterThan(square('Expenses').bottom));
    });

    testWidgets('recording is an action, not a sixth place', (tester) async {
      await open(tester, const MoneyScreen());

      // It was the second of five identical rows. A treasurer standing
      // at a supplier's counter is here to record something, and the
      // one verb on the screen should not look like another list.
      expect(
        find.ancestor(
          of: find.text('Record an expense'),
          matching: find.byType(BrutButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a count it prints is a count it fetches', (tester) async {
      // Receipts and income are not among the lists signing in loads,
      // and the squares now print both. A zero that is really "never
      // asked for" looks exactly like a zero that is true.
      final app = await open(tester, const MoneyScreen());

      expect(app.receipts, isNotEmpty);
      expect(app.incomes, isNotEmpty);
    });
  });

  group('Inventory', () {
    testWidgets('an empty shelf is counted once, under None left', (
      tester,
    ) async {
      final app = await open(tester, const InventoryScreen());
      await tester.pump(const Duration(milliseconds: 400));

      // isLowStock is true at zero, so counting it in both would double
      // -count the same shelf and disagree with the badges on the rows
      // below, which already make this distinction.
      final empty = app.catalog.where((i) => i.quantity <= 0).length;
      final low = app.catalog
          .where((i) => i.quantity > 0 && i.isLowStock)
          .length;

      expect(empty, greaterThan(0), reason: 'the demo needs one to test with');

      Finder figure(String label) => find.ancestor(
        of: find.text(label.toUpperCase()),
        matching: find.byType(StatCell),
      );

      expect(
        find.descendant(of: figure('None left'), matching: find.text('$empty')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: figure('Low stock'), matching: find.text('$low')),
        findsOneWidget,
      );
    });
  });

  group('Flagged', () {
    testWidgets('what causes a flag is on the empty screen too', (
      tester,
    ) async {
      final app = await open(
        tester,
        const RiskScreen(),
        role: UserRole.superAdmin,
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        app.flaggedExpenses,
        isEmpty,
        reason: 'the normal state, and the one this is about',
      );

      // The card explaining what a flag means used to be appended to
      // the end of the list, so it appeared only when there were flags
      // to explain — exactly when it is least needed.
      expect(find.text('What causes a flag'), findsOneWidget);
      expect(find.text('Nothing flagged'), findsOneWidget);
    });
  });

  group('Dashboard', () {
    testWidgets('the next activity says where it has got to', (tester) async {
      final app = await open(tester, const HomeScreen());

      // A date without an approval stage is half the fact: an event in
      // four days that is still with the Dean cannot be spent against.
      final next = app.events.firstWhere((e) => e.on != null);
      expect(find.text('NEXT UP'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BrutBadge),
          matching: find.textContaining(RegExp('With the|Approved|Drafting')),
        ),
        findsWidgets,
        reason: 'the stage, in the same words the proposal bar uses',
      );
      expect(next.on, isNotNull);
    });

    testWidgets('the events square counts what is waiting', (tester) async {
      final app = await open(tester, const HomeScreen());

      final waiting = app.events.where((e) => e.status.isPending).length;
      expect(waiting, greaterThan(0), reason: 'the demo needs some to count');

      // How many exist is a figure nobody acts on, and it was the first
      // thing on the dashboard.
      expect(find.text('Events waiting'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Events waiting'),
            matching: find.byType(BrutCard),
          ).first,
          matching: find.text('$waiting'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the header is two rows, not three', (tester) async {
      await open(tester, const HomeScreen(), size: const Size(420, 900));

      // The date and the scope sit on one row now. Three stacked rows
      // of header meant the thing the app is about started a fifth of
      // the way down the screen.
      final date = tester.getRect(find.textContaining(RegExp(r'^\w{3} / ')));
      final scope = tester.getRect(find.textContaining('TREASURER'));
      expect(date.top, closeTo(scope.top, 1));
      expect(scope.left, greaterThan(date.right));
    });
  });
}
