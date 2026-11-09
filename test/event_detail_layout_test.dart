import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';

/// The event page, grouped.
///
/// It ran status, the facts, an action, the review history and two more
/// actions together as equal cards on one scroll, so finding what you
/// could do meant going past everything else. The same density
/// complaint that split Part 1 applies here, and this is the shape that
/// answers it: three headings, every action under the last of them, and
/// a history that does not grow without limit.
void main() {
  Widget host(AppState app, EventItem event) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
      ChangeNotifierProvider(create: (_) => NoticeShelf()),
    ],
    child: MaterialApp(home: EventDetailScreen(event: event)),
  );

  Future<AppState> open(
    WidgetTester tester, {
    UserRole role = UserRole.treasurer,
    required bool Function(EventItem) pick,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 2600);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: role);
    await tester.pumpWidget(host(app, app.events.firstWhere(pick)));
    await tester.pumpAndSettle();
    return app;
  }

  group('the page is grouped', () {
    testWidgets('it carries the three headings', (tester) async {
      await open(tester, pick: (e) => e.remoteId != null);

      expect(find.text('The activity'), findsOneWidget);
      expect(find.text('What happened'), findsOneWidget);
      expect(find.text('What you can do'), findsOneWidget);
    });

    testWidgets('the actions sit under the last heading, not scattered', (
      tester,
    ) async {
      await open(tester, pick: (e) => e.remoteId != null);

      final heading = tester.getTopLeft(find.text('What you can do')).dy;
      final form = tester.getTopLeft(find.text('Proposal form')).dy;

      expect(
        form,
        greaterThan(heading),
        reason: 'an action above its own heading is the old scattering',
      );
    });

    testWidgets('and the history comes before them', (tester) async {
      await open(tester, pick: (e) => e.remoteId != null);

      expect(
        tester.getTopLeft(find.text('What happened')).dy,
        lessThan(tester.getTopLeft(find.text('What you can do')).dy),
      );
    });
  });

  group('the review history', () {
    // The demo seeds at most three decisions, which is the threshold —
    // so in demo everything shows and no button is offered. That is the
    // behaviour asserted here. The collapsed path belongs to real data,
    // where the nine signature steps are what made this the longest
    // thing on the page, and it is not covered by a test.
    testWidgets('nothing is hidden when there is little to hide', (
      tester,
    ) async {
      final app = await open(
        tester,
        pick: (e) => e.status == EventApprovalStatus.rejected,
      );
      final event = app.events.firstWhere(
        (e) => e.status == EventApprovalStatus.rejected,
      );

      final records = (await app.loadApprovals(event)).records!;
      expect(
        records.length,
        lessThanOrEqualTo(3),
        reason: 'if the seed grows past three, this test should see the '
            'button and should be changed to exercise it',
      );
      expect(find.textContaining('Show all'), findsNothing);
      expect(find.textContaining('Show the latest only'), findsNothing);
    });
  });
}
