import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// The Moderator and the Dean decide on a proposal: they approve it or send
/// it back, and never reject it (that is the SDS Office's alone). A return
/// needs a reason, and every decision names the proposal version it was made
/// on, so a proposal that changed meanwhile is refused instead of overwritten.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Map<String, dynamic> eventJson(String status) => {
    'id': 'e1',
    'category_id': null,
    'title': 'Hack the Future',
    'description': null,
    'proposed_by': 'u-proposer',
    'status': status,
    'event_date': null,
    'estimated_cost': 2500,
    'allocated_budget': 0,
    'remaining_budget': 0,
    'school_year': '2026-2027',
    'semester': null,
    'event_scope': null,
    'department_id': null,
    'organization_id': null,
    'created_at': '2026-10-01T00:00:00Z',
    'updated_at': '2026-10-01T00:00:00Z',
  };

  /// The server for one event, `e1`, as far as this screen asks about it.
  /// [version] is the proposal's, or null for an event that has none (the
  /// proposal route answers 404). [decision] answers an approve or a reject.
  final sent = <http.Request>[];
  int? version = 4;
  Completer<void>? hold;
  http.Response Function(http.Request) decision = (_) => json({});
  List<Map<String, dynamic>> approvals = [];
  http.Response? proposalFailure;

  /// What `GET /events/e1` answers with: where the event has got to by now,
  /// or [eventFailure] when it cannot be read.
  var eventStatus = 'pending_adviser';
  http.Response? eventFailure;

  setUp(() {
    sent.clear();
    version = 4;
    hold = null;
    approvals = [];
    proposalFailure = null;
    eventStatus = 'pending_adviser';
    eventFailure = null;
    decision = (request) => json(
      eventJson(
        request.url.path.endsWith('/approve') ? 'pending_admin' : 'draft',
      ),
    );
  });

  Future<http.Response> serve(http.Request request) async {
    sent.add(request);
    final path = request.url.path;
    if (path.endsWith('/sap-proposal')) {
      await hold?.future;
      if (proposalFailure != null) return proposalFailure!;
      if (version == null) return json({'detail': 'Not Found'}, 404);
      return json({
        'id': 'p1',
        'event_id': 'e1',
        'state': 'pending_department_review',
        'version': version,
        'revision_no': 1,
        'details': {'title': 'Hack the Future'},
        'collections': <String, dynamic>{},
      });
    }
    if (path.endsWith('/approvals')) return json(approvals);
    if (path.endsWith('/approve') || path.endsWith('/reject')) {
      return decision(request);
    }
    if (request.method == 'GET' && path.endsWith('/events/e1')) {
      return eventFailure ?? json(eventJson(eventStatus));
    }
    return json({'detail': 'Not Found'}, 404);
  }

  List<http.Request> posted(String action) => [
    for (final r in sent)
      if (r.method == 'POST' && r.url.path.endsWith('/$action')) r,
  ];

  AppState liveAs(UserRole role) =>
      AppState(apiClient: ApiClient(httpClient: MockClient(serve)))
        ..devQuickLogin(role);

  EventItem eventAt(EventApprovalStatus status, {String? proposedBy}) =>
      EventItem(
        remoteId: 'e1',
        title: 'Hack the Future',
        org: 'ACPES',
        date: '10/28/2026',
        budget: '₱2,500.00',
        status: status,
        proposedBy: proposedBy ?? 'u-proposer',
      );

  Future<void> open(WidgetTester tester, AppState app, EventItem event) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider(create: (_) => AppSettings()),
          ChangeNotifierProvider(create: (_) => Reachability()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EventDetailScreen(event: event),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  BrutButton button(WidgetTester tester, String label, {Finder? within}) =>
      tester.widget<BrutButton>(
        find.descendant(
          of: within ?? find.byType(EventDetailScreen),
          matching: find.widgetWithText(BrutButton, label),
        ),
      );

  bool pressable(WidgetTester tester, String label, {Finder? within}) =>
      button(tester, label, within: within).onPressed != null;

  Future<void> tapRow(WidgetTester tester, String label) async {
    final finder = find.widgetWithText(BrutButton, label);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// The confirm button inside the open dialog, not the row behind it.
  Finder inDialog(String label) => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(BrutButton, label),
  );

  Future<void> tapInDialog(WidgetTester tester, String label) async {
    await tester.tap(inDialog(label));
    await tester.pumpAndSettle();
  }

  Future<void> typeRemarks(
    WidgetTester tester,
    String label,
    String text,
  ) async {
    await tester.enterText(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is BrutTextField && w.label == label,
        ),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.pump();
  }

  group('a proposal offers Return for revision', () {
    testWidgets('to the Moderator at the Moderator\'s step', (tester) async {
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdviser),
      );

      expect(find.text('Return for revision'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('and to the Dean at the Dean\'s', (tester) async {
      await open(
        tester,
        liveAs(UserRole.admin),
        eventAt(EventApprovalStatus.pendingAdmin),
      );

      expect(find.text('Return for revision'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('and in the demo, where every event is one', (tester) async {
      final app = AppState()..enterDemo(role: UserRole.adviser);
      await open(
        tester,
        app,
        app.events.firstWhere(
          (e) => e.status == EventApprovalStatus.pendingAdviser,
        ),
      );

      expect(find.text('Return for revision'), findsOneWidget);
      expect(find.text('Reject'), findsNothing);
    });
  });

  testWidgets('both buttons wait for the proposal to be read', (tester) async {
    hold = Completer<void>();
    await open(
      tester,
      liveAs(UserRole.adviser),
      eventAt(EventApprovalStatus.pendingAdviser),
    );

    expect(pressable(tester, 'Approve'), isFalse);
    expect(pressable(tester, 'Reject'), isFalse);

    hold!.complete();
    await tester.pump(const Duration(milliseconds: 300));

    expect(pressable(tester, 'Approve'), isTrue);
    expect(pressable(tester, 'Return for revision'), isTrue);
  });

  testWidgets(
    'a proposal that cannot be read says why, and can be tried again',
    (tester) async {
      proposalFailure = json({'detail': 'The department service is down'}, 503);
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdviser),
      );

      expect(
        find.textContaining('The department service is down'),
        findsWidgets,
      );
      expect(find.text('Approve'), findsNothing);

      proposalFailure = null;
      await tapRow(tester, 'Try again');

      expect(find.text('Try again'), findsNothing);
      expect(pressable(tester, 'Approve'), isTrue);
      expect(find.text('Return for revision'), findsOneWidget);
    },
  );

  group('a plain event keeps Reject', () {
    testWidgets('and sends no version', (tester) async {
      version = null;
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdviser),
      );

      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Return for revision'), findsNothing);

      await tapRow(tester, 'Reject');
      // Its note is optional, and a blank one is not sent at all.
      expect(find.text('Reject proposal'), findsOneWidget);
      await tapInDialog(tester, 'Reject');

      expect(jsonDecode(posted('reject').single.body), <String, dynamic>{});
    });

    testWidgets('and so does approving it', (tester) async {
      version = null;
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdviser),
      );

      await tapRow(tester, 'Approve');
      expect(find.text('Approve and forward to admin'), findsOneWidget);
      await tapInDialog(tester, 'Approve');

      expect(jsonDecode(posted('approve').single.body), <String, dynamic>{});
    });

    testWidgets('and so does the Dean\'s final approval of it', (tester) async {
      version = null;
      await open(
        tester,
        liveAs(UserRole.admin),
        eventAt(EventApprovalStatus.pendingAdmin),
      );

      await tapRow(tester, 'Approve');

      expect(find.text('Grant final approval'), findsOneWidget);
      expect(find.text('Approve and send to the SDS Office'), findsNothing);
    });
  });

  group('returning a proposal', () {
    testWidgets('needs remarks and sends the version', (tester) async {
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdviser),
      );

      await tapRow(tester, 'Return for revision');
      expect(find.text('Return for revision?'), findsOneWidget);
      expect(
        pressable(tester, 'Return', within: find.byType(AlertDialog)),
        isFalse,
      );

      // Spaces say nothing.
      await typeRemarks(tester, 'What needs changing', '   ');
      expect(
        pressable(tester, 'Return', within: find.byType(AlertDialog)),
        isFalse,
      );

      await typeRemarks(tester, 'What needs changing', 'Fix the budget.');
      expect(
        pressable(tester, 'Return', within: find.byType(AlertDialog)),
        isTrue,
      );

      await tapInDialog(tester, 'Return');

      expect(jsonDecode(posted('reject').single.body), {
        'remarks': 'Fix the budget.',
        'expected_version': 4,
      });
      expect(find.textContaining('Returned for revision'), findsOneWidget);
    });

    testWidgets('is not a rejection of it', (tester) async {
      final app = liveAs(UserRole.adviser);
      final event = eventAt(EventApprovalStatus.pendingAdviser);
      await open(tester, app, event);

      await tapRow(tester, 'Return for revision');
      await typeRemarks(tester, 'What needs changing', 'Fix the budget.');
      await tapInDialog(tester, 'Return');

      // The server made it a draft again; nobody rejected anything.
      expect(event.status, EventApprovalStatus.draft);
      expect(event.rejectedBy, isNull);
    });

    testWidgets('can be left with nothing sent', (tester) async {
      await open(
        tester,
        liveAs(UserRole.admin),
        eventAt(EventApprovalStatus.pendingAdmin),
      );

      await tapRow(tester, 'Return for revision');
      await typeRemarks(tester, 'What needs changing', 'Not yet.');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(posted('reject'), isEmpty);
    });
  });

  testWidgets('approving a proposal sends the version', (tester) async {
    await open(
      tester,
      liveAs(UserRole.admin),
      eventAt(EventApprovalStatus.pendingAdmin),
    );

    await tapRow(tester, 'Approve');
    // A proposal goes on to the SDS Office, not to final approval.
    expect(find.text('Approve and send to the SDS Office'), findsOneWidget);
    expect(find.text('Grant final approval'), findsNothing);
    // Optional here, as it always was.
    await typeRemarks(tester, 'Feedback (optional)', 'Looks good.');
    await tapInDialog(tester, 'Approve');

    expect(jsonDecode(posted('approve').single.body), {
      'remarks': 'Looks good.',
      'expected_version': 4,
    });
  });

  testWidgets('the Moderator\'s approval of a proposal goes to the Dean', (
    tester,
  ) async {
    await open(
      tester,
      liveAs(UserRole.adviser),
      eventAt(EventApprovalStatus.pendingAdviser),
    );

    await tapRow(tester, 'Approve');

    expect(find.text('Approve and send to the Dean'), findsOneWidget);
    expect(find.text('Approve and forward to admin'), findsNothing);
  });

  group('a changed proposal', () {
    const changed = 'This proposal has changed since you opened it';
    const banner =
        'Someone else changed this proposal. Reload it to see their version '
        'before deciding.';

    final staleBanner = find.byWidgetPredicate(
      (w) =>
          w is BrutInlineMessage &&
          w.text == banner &&
          w.tone == BrutTone.coral &&
          w.icon == Icons.sync_problem,
    );

    int proposalReads() => sent
        .where((r) => r.method == 'GET' && r.url.path.endsWith('/sap-proposal'))
        .length;

    /// The server has moved on, and now accepts a decision made on version 5.
    void proposalMovesOn() {
      version = 5;
      decision = (request) => json(
        eventJson(
          request.url.path.endsWith('/approve') ? 'pending_admin' : 'draft',
        ),
      );
    }

    testWidgets('says so, and holds both decisions until it is reloaded', (
      tester,
    ) async {
      decision = (_) => json({'detail': changed}, 409);
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdviser),
      );
      expect(staleBanner, findsNothing);

      await tapRow(tester, 'Approve');
      await tapInDialog(tester, 'Approve');

      // The server's words, and a banner that stays after they are gone.
      expect(find.text(changed), findsOneWidget);
      expect(staleBanner, findsOneWidget);
      expect(pressable(tester, 'Approve'), isFalse);
      expect(pressable(tester, 'Return for revision'), isFalse);
      expect(posted('approve'), hasLength(1));

      // Reading it again is the way on, and nothing is resent for them.
      proposalMovesOn();
      await tapRow(tester, 'Reload the proposal');

      expect(proposalReads(), 2);
      expect(posted('approve'), hasLength(1));
      expect(staleBanner, findsNothing);
      expect(pressable(tester, 'Approve'), isTrue);
      expect(pressable(tester, 'Return for revision'), isTrue);

      await tapRow(tester, 'Approve');
      await tapInDialog(tester, 'Approve');

      expect(posted('approve'), hasLength(2));
      expect(jsonDecode(posted('approve').last.body), {'expected_version': 5});
    });

    testWidgets('keeps the reason that was typed for a return', (tester) async {
      decision = (_) => json({'detail': changed}, 409);
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdviser),
      );

      await tapRow(tester, 'Return for revision');
      await typeRemarks(tester, 'What needs changing', 'Fix the budget.');
      await tapInDialog(tester, 'Return');

      expect(find.text(changed), findsOneWidget);
      expect(staleBanner, findsOneWidget);
      expect(pressable(tester, 'Return for revision'), isFalse);

      proposalMovesOn();
      await tapRow(tester, 'Reload the proposal');
      await tapRow(tester, 'Return for revision');

      // Written already, and ready to send.
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, 'Fix the budget.');
      expect(
        pressable(tester, 'Return', within: find.byType(AlertDialog)),
        isTrue,
      );

      await tapInDialog(tester, 'Return');

      expect(jsonDecode(posted('reject').last.body), {
        'remarks': 'Fix the budget.',
        'expected_version': 5,
      });
    });

    testWidgets('does not keep a reason that was abandoned', (tester) async {
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdviser),
      );

      await tapRow(tester, 'Return for revision');
      await typeRemarks(tester, 'What needs changing', 'Not yet.');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tapRow(tester, 'Return for revision');

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('is not what an approval refused for blockers is', (
      tester,
    ) async {
      // Also a 409, but reading the proposal again would not clear these.
      decision = (_) => json({
        'detail': {
          'message': 'Not ready for approval',
          'blockers': ['Part 4 is missing'],
        },
      }, 409);
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdviser),
      );

      await tapRow(tester, 'Approve');
      await tapInDialog(tester, 'Approve');

      expect(find.textContaining('Part 4 is missing'), findsOneWidget);
      expect(staleBanner, findsNothing);
      expect(pressable(tester, 'Approve'), isTrue);
    });

    testWidgets('that is no longer this reviewer\'s turn drops the row', (
      tester,
    ) async {
      // The server checks the version, then whose turn it is, and answers the
      // second with a plain 409 too. Reading the proposal again cannot clear
      // it: only the event's own status can, so a reload reads that as well.
      decision = (_) => json({
        'detail': 'This proposal is not waiting on department review',
      }, 409);
      final event = eventAt(EventApprovalStatus.pendingAdviser);
      await open(tester, liveAs(UserRole.adviser), event);

      await tapRow(tester, 'Approve');
      await tapInDialog(tester, 'Approve');
      expect(staleBanner, findsOneWidget);

      eventStatus = 'pending_institutional_review';
      await tapRow(tester, 'Reload the proposal');

      expect(find.text('Approve'), findsNothing);
      expect(find.text('Return for revision'), findsNothing);
      expect(staleBanner, findsNothing);
      expect(posted('approve'), hasLength(1));
      expect(event.status, EventApprovalStatus.pendingInstitutional);
      expect(
        find.widgetWithText(BrutBadge, 'With the signatories'),
        findsOneWidget,
      );
    });

    testWidgets('and an event that cannot be read says why, and can be '
        'tried again', (tester) async {
      decision = (_) => json({'detail': changed}, 409);
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdviser),
      );
      await tapRow(tester, 'Approve');
      await tapInDialog(tester, 'Approve');

      eventFailure = json({'detail': 'The event service is down'}, 503);
      await tapRow(tester, 'Reload the proposal');

      expect(find.textContaining('The event service is down'), findsWidgets);
      expect(find.text('Approve'), findsNothing);

      eventFailure = null;
      proposalMovesOn();
      await tapRow(tester, 'Try again');

      expect(find.text('Try again'), findsNothing);
      expect(staleBanner, findsNothing);
      expect(pressable(tester, 'Approve'), isTrue);
    });
  });

  testWidgets('a proposal read that is refused shows what the server said', (
    tester,
  ) async {
    proposalFailure = json({'detail': 'The proposal is being edited'}, 409);
    await open(
      tester,
      liveAs(UserRole.adviser),
      eventAt(EventApprovalStatus.pendingAdviser),
    );

    expect(find.textContaining('The proposal is being edited'), findsWidgets);
    expect(find.textContaining('Instance of'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  group('nobody decides their own', () {
    testWidgets('proposal, whatever the button would be called', (
      tester,
    ) async {
      // In the demo every event is a proposal, and the treasurer wrote them.
      final app = AppState()..enterDemo(role: UserRole.treasurer);
      await open(
        tester,
        app,
        app.events.firstWhere(
          (e) => e.status == EventApprovalStatus.pendingAdviser,
        ),
      );

      expect(find.text('Return for revision'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('and the Dean is not offered the Moderator\'s step', (
      tester,
    ) async {
      await open(
        tester,
        liveAs(UserRole.admin),
        eventAt(EventApprovalStatus.pendingAdviser),
      );

      expect(find.text('Return for revision'), findsNothing);
      expect(find.text('Approve'), findsNothing);
      expect(
        sent.where((r) => r.url.path.endsWith('/sap-proposal')),
        isEmpty,
        reason: 'no row, so nothing to read the proposal for',
      );
    });

    testWidgets('nor the Moderator the Dean\'s', (tester) async {
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdmin),
      );

      expect(find.text('Return for revision'), findsNothing);
      expect(find.text('Approve'), findsNothing);
    });
  });

  testWidgets('the history names a return', (tester) async {
    approvals = [
      {
        'id': 'a1',
        'entity_type': 'event',
        'entity_id': 'e1',
        'step_order': 1,
        'reviewer_id': 'u-adviser',
        'decision': 'returned',
        'remarks': 'Fix the budget.',
        'decided_at': '2026-11-03T08:00:00Z',
      },
    ];
    await open(
      tester,
      liveAs(UserRole.treasurer),
      eventAt(EventApprovalStatus.draft),
    );

    expect(find.text('Returned for revision'), findsOneWidget);
    final coral = BrutTone.coral.fill(
      tester.element(find.byType(EventDetailScreen)),
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration! as BoxDecoration).color == coral,
      ),
      findsOneWidget,
    );
  });
}
