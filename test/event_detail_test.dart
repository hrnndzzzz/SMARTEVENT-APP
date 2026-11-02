import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// A rejected proposal does not always know who rejected it — a legacy
/// row, or one seeded before the field existed, carries no reviewer. The
/// screen used to interpolate that straight into the sentence and print
/// "Rejected by null." on the card a reviewer reads first.
void main() {
  Widget host(EventItem event, {AppState? signedInAs}) {
    final app = signedInAs ?? (AppState()..devQuickLogin(UserRole.treasurer));
    return MultiProvider(
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
  }

  EventItem rejected({String? by, String? note}) => EventItem(
    title: 'Alumni Homecoming Night',
    org: 'ICpEP.SE',
    date: '11/21/2026',
    budget: '₱5,000.00',
    status: EventApprovalStatus.rejected,
    rejectedBy: by,
    adminApprovalNote: note,
  );

  testWidgets('an unknown reviewer is not printed as null', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(rejected()));
    await tester.pump();

    expect(find.textContaining('null'), findsNothing);
    expect(find.textContaining('This proposal was rejected'), findsOneWidget);
  });

  testWidgets('a known reviewer is still named', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(rejected(by: 'Adviser')));
    await tester.pump();

    // Twice over: the status badge and the card below it.
    expect(find.textContaining('Rejected by Adviser'), findsWidgets);
    expect(find.textContaining('null'), findsNothing);
  });

  // The SDS Office's rejection is final, so there is nothing to edit: the
  // button that used to say "Edit proposal" only opens the proposal.
  testWidgets('a rejected proposal is opened, not edited', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(rejected()));
    await tester.pump();

    expect(find.text('Open proposal'), findsOneWidget);
    expect(find.text('Edit proposal'), findsNothing);
  });

  /// The demo has no server, so the form follows the event's status.
  testWidgets('the proposal form opens where the event has got to', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.reset);

    for (final (status, state) in [
      (EventApprovalStatus.draft, SapState.draft),
      (EventApprovalStatus.pendingAdviser, SapState.pendingDepartmentReview),
      (EventApprovalStatus.pendingAdmin, SapState.pendingDepartmentReview),
      (EventApprovalStatus.pendingInstitutional, SapState.pendingReview),
      (EventApprovalStatus.rejected, SapState.rejected),
      (EventApprovalStatus.approved, SapState.approved),
      (EventApprovalStatus.completed, SapState.completed),
    ]) {
      // A fresh tree each time: the last one has the form on top.
      await tester.pumpWidget(const SizedBox.shrink());
      final event = EventItem(
        remoteId: 'e1',
        title: 'Hack the Future',
        org: 'ACPES',
        date: '10/28/2026',
        budget: '₱2,500.00',
        status: status,
      );
      await tester.pumpWidget(
        host(
          event,
          signedInAs: AppState()..enterDemo(role: UserRole.treasurer),
        ),
      );
      await tester.pumpAndSettle();

      final open = find.widgetWithText(BrutButton, 'Proposal form');
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();

      expect(
        tester.widget<SapFormScreen>(find.byType(SapFormScreen)).form.state,
        state,
        reason: status.name,
      );
    }
  });

  EventItem at(EventApprovalStatus status) => EventItem(
    title: 'Hack the Future',
    org: 'ACPES',
    date: '10/28/2026',
    budget: '\u20b12,500.00',
    status: status,
  );

  /// Taking a proposal back puts it in draft. The adviser chip asked
  /// whether the event was NOT in adviser review, which a draft also
  /// satisfies \u2014 so withdrawing ticked the adviser step green, claiming
  /// a decision nobody had made.
  group('the adviser stage is past it, not merely out of it', () {
    Future<void> show(WidgetTester tester, EventApprovalStatus status) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(at(status)));
      await tester.pump();
    }

    testWidgets('a draft has not passed adviser review', (tester) async {
      await show(tester, EventApprovalStatus.draft);

      expect(
        find.byIcon(Icons.check_circle),
        findsNothing,
        reason: 'nothing has been decided on a draft',
      );
    });

    testWidgets('waiting on the adviser is shown as waiting', (tester) async {
      await show(tester, EventApprovalStatus.pendingAdviser);

      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('with the admin, the adviser is done', (tester) async {
      await show(tester, EventApprovalStatus.pendingAdmin);

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    });

    testWidgets('approved ticks both', (tester) async {
      await show(tester, EventApprovalStatus.approved);

      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    });
  });
}
