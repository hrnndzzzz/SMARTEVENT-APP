import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/screens/events_hub_screen.dart';
import 'package:smartevent/screens/sap/sap_cover_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// A proposal waiting on a decision does not stop a new one.
void main() {
  Widget host(AppState app, Widget screen) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: screen),
  );

  testWidgets('the band starts a new proposal while one is pending', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    expect(app.events.any((e) => e.status.isPending), isTrue);

    await tester.pumpWidget(host(app, const EventsHubScreen()));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Create\nevent'), findsOneWidget);
    expect(find.text('See\nproposal'), findsNothing);

    await tester.tap(find.text('Create\nevent'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(SapCoverScreen), findsOneWidget);
    expect(find.byType(EventDetailScreen), findsNothing);
  });
}
