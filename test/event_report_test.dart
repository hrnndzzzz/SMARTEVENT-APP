import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/screens/event_report_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// G8, a financial report per event.
///
/// The backend answered `/reports/event/{id}` all along and the client
/// carried `eventReport`, `exportEvent` and `loadEventReport` — with no
/// screen opening any of them, so none of it had ever been seen. The
/// way in gets a test, as every way in on this project now does.
void main() {
  Widget host(AppState app, Widget screen) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: screen),
  );

  Future<void> open(WidgetTester tester, Widget w, AppState app) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(app, w));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a finished event offers its report', (tester) async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final event = app.events.firstWhere((e) => e.status.isResolved);

    await open(tester, EventDetailScreen(event: event), app);

    expect(find.text('Financial report'), findsOneWidget);
  });

  testWidgets('a draft does not — there is nothing to liquidate', (
    tester,
  ) async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final event = app.events.firstWhere((e) => e.status.isDraft);

    await open(tester, EventDetailScreen(event: event), app);

    expect(find.text('Financial report'), findsNothing);
  });

  testWidgets('the report shows the figures and offers the file', (
    tester,
  ) async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final event = app.events.firstWhere((e) => e.remoteId == 'demo-ev-2');

    await open(tester, EventReportScreen(event: event), app);

    expect(find.text('The figures'), findsOneWidget);
    // BrutDetailRow renders its label uppercase, as everywhere else.
    expect(find.text('ALLOCATED'), findsOneWidget);
    expect(find.text('APPROVED SPENDING'), findsOneWidget);
    expect(find.text('Net balance'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('CSV'), findsOneWidget);
  });

  testWidgets('withheld income is named, not folded into the total', (
    tester,
  ) async {
    // Withheld income is not income until someone decides, so a report
    // that silently added it in would overstate what the event took.
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final event = app.events.firstWhere((e) => e.remoteId == 'demo-ev-5');

    await open(tester, EventReportScreen(event: event), app);

    expect(find.textContaining('withheld'), findsOneWidget);
    expect(find.textContaining('not counted above'), findsOneWidget);
  });
}
