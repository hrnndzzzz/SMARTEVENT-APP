import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/events_hub_screen.dart';
import 'package:smartevent/screens/sap/sap_cover_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Band one names the newest draft, so tapping it has to carry on with
/// that draft rather than start a second proposal beside it.
Future<AppState> pumpHub(
  WidgetTester tester,
  EventApprovalStatus status,
) async {
  final app = AppState()..enterDemo(role: UserRole.treasurer);
  // Begun by someone else in the organization: the president starts a
  // draft and asks the vice-president to finish it.
  app.events.first
    ..status = status
    ..proposedBy = 'demo-account-president';

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        // A fresh navigator each call: the last one left the form on top.
        key: UniqueKey(),
        theme: AppTheme.light(),
        home: const EventsHubScreen(),
      ),
    ),
  );
  return app;
}

/// Returns the event the opened form belongs to: null for a new proposal.
Future<String?> openFromBandOne(
  WidgetTester tester,
  EventApprovalStatus status,
) async {
  final app = await pumpHub(tester, status);
  await tester.tap(find.text(app.events.first.title));
  await tester.pumpAndSettle();

  return tester
      .widget<SapCoverScreen>(find.byType(SapCoverScreen))
      .form
      .eventId;
}

void main() {
  testWidgets('tapping band one carries on with the newest draft, whoever '
      'began it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));

    // demo-ev-1 is the demo's newest event.
    expect(
      await openFromBandOne(tester, EventApprovalStatus.draft),
      'demo-ev-1',
    );
  });

  testWidgets('and says so, instead of offering to create one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await pumpHub(tester, EventApprovalStatus.draft);

    expect(find.text('Continue\ndraft'), findsOneWidget);
  });

  testWidgets('in every other settled state it starts a new proposal', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));

    for (final status in EventApprovalStatus.values) {
      // A draft is carried on rather than duplicated, and a proposal
      // waiting on a decision stops a second one being started at all
      // — one at a time. Both open something instead of a blank form,
      // so neither belongs in this list.
      if (status == EventApprovalStatus.draft || status.isPending) continue;
      expect(
        await openFromBandOne(tester, status),
        isNull,
        reason: '$status opened an existing event',
      );
    }
  });

  testWidgets('and a proposal awaiting a decision starts nothing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));

    for (final status in EventApprovalStatus.values.where((s) => s.isPending)) {
      await pumpHub(tester, status);
      await tester.pumpAndSettle();

      expect(
        find.byType(SapCoverScreen),
        findsNothing,
        reason: '$status let a second proposal be started',
      );
    }
  });
}
