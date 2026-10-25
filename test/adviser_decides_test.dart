import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// An adviser looking at an event that is waiting on them has one job,
/// and the screen has to offer it.
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

  Future<void> open(WidgetTester tester, AppState app, EventItem event) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(app, event));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the adviser is offered the decision', (tester) async {
    final app = AppState()..enterDemo(role: UserRole.adviser);
    final event = app.events.firstWhere(
      (e) => e.status == EventApprovalStatus.pendingAdviser,
    );

    await open(tester, app, event);

    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('and is not offered the proposer\'s withdrawal', (tester) async {
    // Taking a proposal back belongs to whoever wrote it. The server
    // refuses it for anyone else, so offering it is offering a 403.
    final app = AppState()..enterDemo(role: UserRole.adviser);
    final event = app.events.firstWhere(
      (e) => e.status == EventApprovalStatus.pendingAdviser,
    );

    await open(tester, app, event);

    expect(find.text('Cancel this proposal'), findsNothing);
  });

  testWidgets('the proposer keeps their own withdrawal', (tester) async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final event = app.events.firstWhere(
      (e) => e.status == EventApprovalStatus.pendingAdviser,
    );

    await open(tester, app, event);

    expect(find.text('Cancel this proposal'), findsOneWidget);
  });

  testWidgets('and still does not decide on it', (tester) async {
    // The guard that matters: nobody reviews their own proposal, which
    // the API enforces anyway.
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final event = app.events.firstWhere(
      (e) => e.status == EventApprovalStatus.pendingAdviser,
    );

    await open(tester, app, event);

    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('an admin does not decide the adviser stage', (tester) async {
    final app = AppState()..enterDemo(role: UserRole.admin);
    final event = app.events.firstWhere(
      (e) => e.status == EventApprovalStatus.pendingAdviser,
    );

    await open(tester, app, event);

    expect(
      find.text('Approve'),
      findsNothing,
      reason: 'the adviser stage is not the admin stage',
    );
  });
}
