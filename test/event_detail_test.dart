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

  // The budget is stored as text, and its shape depends on who wrote it:
  // the backend path stores it formatted, a locally created or seeded
  // event stores bare digits. The screen used to print whichever it was
  // handed, so the demo's proposals read "2500" where every other amount
  // in the app reads "\u20b12,500.00".
  testWidgets('a budget stored as bare digits is shown as money',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        EventItem(
          title: 'Alumni Homecoming Night',
          org: 'ICpEP.SE',
          date: '11/21/2026',
          budget: '2500',
          status: EventApprovalStatus.draft,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('\u20b12,500.00'), findsOneWidget);
    expect(find.text('2500'), findsNothing);
  });

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

  // The SDS Office's rejection is final, so there is nothing to edit. The
  // "Edit proposal" button went, and so did the "Open proposal" it was
  // renamed to: "Proposal form" already opens the proposal.
  testWidgets('a rejected proposal has no edit button', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(rejected()));
    await tester.pump();

    expect(find.text('Edit proposal'), findsNothing);
    expect(find.text('Open proposal'), findsNothing);
  });

  /// A second button into a rejected proposal opened a blank, editable form
  /// in the demo, which "Proposal form" seeds from the event.
  testWidgets('and "Proposal form" is its one way in, showing the rejection', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.reset);

    final event = EventItem(
      remoteId: 'e1',
      title: 'Industry Immersion Talk',
      org: 'ACPES',
      date: '11/05/2026',
      budget: '₱8,000.00',
      status: EventApprovalStatus.rejected,
    );
    await tester.pumpWidget(
      host(event, signedInAs: AppState()..enterDemo(role: UserRole.treasurer)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) => w is BrutButton && w.label.toLowerCase().contains('proposal'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(BrutButton, 'Proposal form'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is BrutInlineMessage &&
            w.text.contains('Rejected by the SDS Office'),
      ),
      findsOneWidget,
    );
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

      // And it lets the proposer send it again only where that is theirs to
      // do: a seeded rejected or department-review proposal used to keep
      // "Submit for review" lit, since the demo form has no server. Where it
      // is theirs, it is offered: lit, or saying what to fill in first.
      final submit = find.widgetWithText(BrutButton, 'Submit for review');
      final offered =
          tester.widget<BrutButton>(submit).onPressed != null ||
          find.textContaining('To send it for review').evaluate().isNotEmpty;
      expect(
        offered,
        state.isProposerEditable,
        reason: '${status.name} offers sending it again',
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

    // The SDS Office has it, so the Dean has approved: it follows the Dean's
    // approval in both flows. The chip stayed grey as if nobody had it yet.
    testWidgets('with the SDS Office, both are done', (tester) async {
      await show(tester, EventApprovalStatus.pendingInstitutional);

      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
      expect(find.byIcon(Icons.hourglass_top), findsNothing);
    });

    testWidgets('approved ticks both', (tester) async {
      await show(tester, EventApprovalStatus.approved);

      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    });
  });
}
