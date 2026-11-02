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
import 'package:smartevent/screens/home_screen.dart';
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

  setUp(() {
    sent.clear();
    version = 4;
    hold = null;
    approvals = [];
    proposalFailure = null;
    decision = (request) => json(
      eventJson(request.url.path.endsWith('/approve') ? 'pending_admin' : 'draft'),
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

  Future<void> typeRemarks(WidgetTester tester, String label, String text) async {
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

  testWidgets('a proposal that cannot be read says why, and can be tried again', (
    tester,
  ) async {
    proposalFailure = json({'detail': 'The department service is down'}, 503);
    await open(
      tester,
      liveAs(UserRole.adviser),
      eventAt(EventApprovalStatus.pendingAdviser),
    );

    expect(find.textContaining('The department service is down'), findsWidgets);
    expect(find.text('Approve'), findsNothing);

    proposalFailure = null;
    await tapRow(tester, 'Try again');

    expect(find.text('Try again'), findsNothing);
    expect(pressable(tester, 'Approve'), isTrue);
    expect(find.text('Return for revision'), findsOneWidget);
  });

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
      await tapInDialog(tester, 'Approve');

      expect(jsonDecode(posted('approve').single.body), <String, dynamic>{});
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
      expect(pressable(tester, 'Return', within: find.byType(AlertDialog)), isFalse);

      // Spaces say nothing.
      await typeRemarks(tester, 'What needs changing', '   ');
      expect(pressable(tester, 'Return', within: find.byType(AlertDialog)), isFalse);

      await typeRemarks(tester, 'What needs changing', 'Fix the budget.');
      expect(pressable(tester, 'Return', within: find.byType(AlertDialog)), isTrue);

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
    // Optional here, as it always was.
    await typeRemarks(tester, 'Feedback (optional)', 'Looks good.');
    await tapInDialog(tester, 'Approve');

    expect(jsonDecode(posted('approve').single.body), {
      'remarks': 'Looks good.',
      'expected_version': 4,
    });
  });

  group('a changed proposal', () {
    const changed = 'This proposal has changed since you opened it';

    testWidgets('says so, and the buttons stay usable', (tester) async {
      decision = (_) => json({'detail': changed}, 409);
      await open(
        tester,
        liveAs(UserRole.adviser),
        eventAt(EventApprovalStatus.pendingAdviser),
      );

      await tapRow(tester, 'Approve');
      await tapInDialog(tester, 'Approve');

      expect(find.text(changed), findsOneWidget);
      expect(pressable(tester, 'Approve'), isTrue);
      expect(pressable(tester, 'Return for revision'), isTrue);
    });

    testWidgets('is said the same way when returning', (tester) async {
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
      expect(pressable(tester, 'Return for revision'), isTrue);
    });
  });

  group('nobody decides their own', () {
    testWidgets('proposal, whatever the button would be called', (tester) async {
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

  group('each reviewer counts only their own step', () {
    Future<void> alertFor(WidgetTester tester, UserRole role) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = AppState()..enterDemo(role: role);
      app.events
        ..clear()
        ..addAll([
          eventAt(EventApprovalStatus.pendingAdviser),
          eventAt(EventApprovalStatus.pendingAdviser),
          eventAt(EventApprovalStatus.pendingAdmin),
        ]);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: const MaterialApp(home: Scaffold(body: AlertWidget())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('the Moderator, the two at the Moderator\'s step', (
      tester,
    ) async {
      await alertFor(tester, UserRole.adviser);

      expect(find.text('2 events awaiting a decision'), findsOneWidget);
    });

    testWidgets('the Dean, the one at the Dean\'s', (tester) async {
      await alertFor(tester, UserRole.admin);

      expect(find.text('1 event awaiting a decision'), findsOneWidget);
    });

    testWidgets('and the Super Admin the same', (tester) async {
      await alertFor(tester, UserRole.superAdmin);

      expect(find.text('1 event awaiting a decision'), findsOneWidget);
    });

    testWidgets('the SDS Office, the ones that have reached it', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = AppState()..enterDemo(role: UserRole.sdsStaff);
      app.events
        ..clear()
        ..addAll([
          eventAt(EventApprovalStatus.pendingAdviser),
          eventAt(EventApprovalStatus.pendingAdmin),
          eventAt(EventApprovalStatus.pendingInstitutional),
        ]);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: const MaterialApp(home: Scaffold(body: AlertWidget())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1 event awaiting a decision'), findsOneWidget);
    });
  });
}
