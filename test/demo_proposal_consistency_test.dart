import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// One event, one proposal, whoever is looking.
///
/// The SDS Office's summary seeded its details, budget and support from
/// DemoProposals while the proposer's own six-part form seeded only the
/// state — so in the demo the office read a full proposal and the
/// student who wrote it saw "0 of 6 parts filled in" for the same event.
void main() {
  Widget host(AppState app, EventItem event) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: EventDetailScreen(event: event),
    ),
  );

  testWidgets('the proposer opens the proposal the office is reading', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final event = app.events.firstWhere((e) => e.remoteId == 'demo-ev-1');

    await tester.pumpWidget(host(app, event));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Proposal form'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // The hub is open, so Part 1 is there to judge.
    expect(find.text('Activity Details'), findsOneWidget);
    expect(
      find.text('Filled in'),
      findsWidgets,
      reason: 'the office reads a full proposal for this very event',
    );
  });
}
