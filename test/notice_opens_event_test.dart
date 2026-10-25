import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/models/notification.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/widgets/notification_menu.dart';

/// Built and unreachable is not built.
///
/// The deep-link from a workflow notice was first written into
/// NotificationsScreen, which nothing in the app opens — the fourth
/// screen in this project to be written, tested and left with no way in.
/// The panel below the bell is what people actually tap, so the way in
/// gets a test of its own.
void main() {
  Widget host(AppState app) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
      ChangeNotifierProvider(create: (_) => NoticeShelf()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => NotificationMenu.show(context),
              child: const Text('bell'),
            ),
          ),
        ),
      ),
    ),
  );

  AppNotice workflowNotice({String? eventId}) => AppNotice(
    id: 'n1',
    kind: 'sap_workflow',
    title: 'SAP proposal submitted',
    body: 'Sent to the SDS Office.',
    readAt: DateTime.now(),
    emailStatus: 'sent',
    createdAt: DateTime.now(),
    payload: eventId == null ? const {} : {'event_id': eventId},
  );

  testWidgets('a workflow notice opens the event it names', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final target = app.events.firstWhere((e) => e.remoteId != null);
    app.notices = [workflowNotice(eventId: target.remoteId)];

    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('bell'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('SAP proposal submitted'), findsOneWidget);

    await tester.tap(find.text('SAP proposal submitted'));
    // The panel pops and the event pushes: two transitions, so pump
    // through both rather than guessing one duration.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      find.byType(EventDetailScreen),
      findsOneWidget,
      reason: 'the notice named an event and the panel must go there',
    );
  });

  testWidgets('a notice with no event only reads', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: UserRole.treasurer);
    app.notices = [workflowNotice()];

    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('bell'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('SAP proposal submitted'));
    // The panel pops and the event pushes: two transitions, so pump
    // through both rather than guessing one duration.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      find.byType(EventDetailScreen),
      findsNothing,
      reason: 'a registration confirmation has nowhere to go',
    );
  });
}
