import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/main.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// The record button and the two things it kept colliding with — B7.
///
/// Floating over the dashboard it covered the allocated and spent
/// figures whenever the screen sat at rest, and padding could not fix
/// that: a floating button over a scrolling list covers whatever is
/// under it, and the bottom padding only clears the last card at full
/// scroll. Docked into the navigation bar instead, it punched through
/// the bar's own edge. It has a band of its own now, between the two.
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

  Rect buttonOn(WidgetTester tester) =>
      tester.getRect(find.bySemanticsLabel('Record an expense').first);

  testWidgets('no dashboard content can sit under it', (tester) async {
    // Stronger than checking the figures one by one: a figure scrolled
    // below the fold still has a rectangle down there, so comparing
    // against each label measured clipping rather than covering. If the
    // button is outside the scrollable, nothing in it can be covered at
    // any scroll position.
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    await openDashboard(tester, app);

    final viewport = tester.getRect(find.byType(Scrollable).first);

    expect(
      buttonOn(tester).top,
      greaterThanOrEqualTo(viewport.bottom),
      reason: 'the button reaches back into the scrolling content',
    );
  });

  testWidgets('and it leaves the navigation bar whole', (tester) async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    await openDashboard(tester, app);

    final button = buttonOn(tester);

    for (final label in ['MENU', 'DASHBOARD', 'EVENTS']) {
      expect(find.text(label), findsOneWidget, reason: '$label went missing');
      expect(
        button.overlaps(tester.getRect(find.text(label))),
        isFalse,
        reason: '$label is under the record button',
      );
    }
  });

  testWidgets('only an account that may record money is offered it', (
    tester,
  ) async {
    final app = AppState()..enterDemo(role: UserRole.officer);
    await openDashboard(tester, app);

    expect(find.bySemanticsLabel('Record an expense'), findsNothing);
  });
}
