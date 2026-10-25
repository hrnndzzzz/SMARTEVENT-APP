import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/search_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// The count beside "Results for …" and the list under it are built from
/// the same list, so they must agree. On the phone a search for "hack"
/// said 2 found and drew one card: the seeded expense whose vendor is
/// "Speaker honorarium — Hack the Future" was counted and not shown.
void main() {
  Widget host(AppState app) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: const SearchScreen()),
  );

  /// Every rendered card carries exactly one of these kind labels. The
  /// badge is mono, so what reaches the screen is uppercase.
  int cardsOn(WidgetTester tester) => const [
    'EVENT',
    'TRANSACTION',
    'CATEGORY',
    'ITEM',
    'SCREEN',
  ].fold(0, (sum, kind) => sum + tester.widgetList(find.text(kind)).length);

  int statedOn(WidgetTester tester) {
    final label = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere(
          (s) => s.toLowerCase().endsWith(' found'),
          orElse: () => throw StateError('no result count on screen'),
        );
    return int.parse(label.split(' ').first);
  }

  testWidgets('the count matches the cards drawn', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: UserRole.treasurer);
    // Not pumpAndSettle: the header's wordmark pulses on a repeating
    // animation, so the tree never reaches a settled frame.
    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).first, 'hack');
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      cardsOn(tester),
      statedOn(tester),
      reason: 'a counted result that is never drawn is a result lost',
    );
  });

  testWidgets('a status tag carries its own colour, not always green', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: UserRole.treasurer);
    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).first, 'hack');
    await tester.pump(const Duration(milliseconds: 300));

    final tag = tester.widget<BrutBadge>(
      find.widgetWithText(BrutBadge, 'Pending Adviser Review'),
    );

    expect(
      tag.tone,
      BrutTone.sun,
      reason: 'waiting on a decision is not the same news as approved',
    );
  });
}
