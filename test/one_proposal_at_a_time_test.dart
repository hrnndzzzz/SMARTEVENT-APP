import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/screens/events_hub_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// F10: no new event while one is pending.
///
/// It was filed as blocked on the backend and never needed it — this
/// is a rule about the events already loaded.
void main() {
  Widget host(AppState app, Widget screen) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: screen),
  );

  Future<void> open(WidgetTester tester, AppState app) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(app, const EventsHubScreen()));
    await tester.pump(const Duration(milliseconds: 400));
  }

  test('a pending proposal is the one holding the queue', () {
    final app = AppState()..enterDemo(role: UserRole.treasurer);

    final waiting = app.proposalAwaitingDecision;

    expect(waiting, isNotNull);
    expect(waiting!.status.isPending, isTrue);
  });

  test('a draft does not hold it — nobody is waiting on an unsent draft', () {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    for (final event in app.events) {
      event.status = EventApprovalStatus.draft;
    }

    expect(app.proposalAwaitingDecision, isNull);
  });

  testWidgets('the band opens the proposal instead of starting another', (
    tester,
  ) async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    await open(tester, app);

    expect(find.text('See\nproposal'), findsOneWidget);

    await tester.tap(find.text('See\nproposal'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      find.byType(EventDetailScreen),
      findsOneWidget,
      reason: 'a band that did nothing would read as broken',
    );
  });

  testWidgets('and offers to create once nothing is waiting', (tester) async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    for (final event in app.events) {
      event.status = EventApprovalStatus.completed;
    }
    await open(tester, app);

    expect(find.text('Create\nevent'), findsOneWidget);
    expect(find.text('See\nproposal'), findsNothing);
  });
}
