import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/main.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// The record button used to float over the dashboard, and at rest it
/// sat on top of the allocated and spent figures — the moderator's B7.
/// Padding could not fix that: a button floating over a scrolling list
/// covers whatever happens to be under it, and the bottom padding only
/// clears the last card at full scroll. It is docked to the navigation
/// bar instead, where it overlaps the bar it rises from and nothing
/// that carries a number.
void main() {
  Future<void> openDashboard(WidgetTester tester, AppState app) async {
    // The phone this is demonstrated on.
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider(create: (_) => AppSettings()),
          ChangeNotifierProvider(create: (_) => Reachability()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const RootShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('it covers none of the dashboard figures', (tester) async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    await openDashboard(tester, app);

    final button = tester.getRect(
      find.bySemanticsLabel('Record an expense').first,
    );

    for (final label in [
      'REMAINING BUDGET',
      'AWAITING REVIEW',
      'ALLOCATED',
      'APPROVED SPENDING',
      'BUDGET USED',
    ]) {
      final found = find.text(label);
      if (found.evaluate().isEmpty) continue;
      expect(
        button.overlaps(tester.getRect(found)),
        isFalse,
        reason: '$label is under the record button',
      );
    }
  });

  testWidgets('and only a treasurer is offered it', (tester) async {
    // It follows what the server says this account may do, like every
    // other money control.
    final app = AppState()..enterDemo(role: UserRole.officer);
    await openDashboard(tester, app);

    expect(find.bySemanticsLabel('Record an expense'), findsNothing);
  });

  testWidgets('it stands in for the tab it covers, and only there', (
    tester,
  ) async {
    // The circle is wider than a label is tall, so the word underneath
    // peeked out around it. The slot keeps its width and draws nothing
    // while the button is there — the covered tab is the page you are
    // already on.
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    await openDashboard(tester, app);

    // The bar renders its labels uppercase.
    expect(find.text('DASHBOARD'), findsNothing);
    expect(find.text('MENU'), findsOneWidget);
    expect(find.text('EVENTS'), findsOneWidget);

    // Off the dashboard the button goes and the tab comes back.
    await tester.tap(find.text('MENU'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.bySemanticsLabel('Record an expense'), findsNothing);
  });
}
