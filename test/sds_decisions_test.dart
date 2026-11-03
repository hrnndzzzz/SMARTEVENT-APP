import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/screens/sap/sds_sign_screen.dart';
import 'package:smartevent/screens/sap/signature_pad.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// The SDS Office decides from one screen: approve and sign, return, or
/// reject.
///
/// Returning and rejecting both owe the organization a reason, so neither is
/// offered until the overall remark is written, and neither waits for Part 4,
/// which only the signature needs. Rejecting is final, so both confirm first.
void main() {
  late List<http.Request> requests;
  var conflict = false;

  /// The version and state a read of the proposal answers with.
  var served = 3;
  var servedState = 'pending_sap_review';

  /// Holds every request that is not a read until it completes, so a test can
  /// look at the screen while one is in flight.
  Completer<void>? hold;

  setUp(() {
    requests = [];
    hold = null;
    conflict = false;
    served = 3;
    servedState = 'pending_sap_review';
  });

  http.Response json(Map<String, dynamic> body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  Map<String, dynamic> proposal(
    String state, {
    required int version,
    bool cleared = true,
    String? remarks,
  }) => {
    'id': 'p1',
    'event_id': 'e1',
    'state': state,
    'version': version,
    'revision_no': 1,
    'details': {'title': 'Hack the Future'},
    'collections': <String, dynamic>{},
    if (cleared)
      'clearance': {
        'parents_consent': 'yes',
        'attachments': 'Program and budget',
        'class_interruption': 'none',
        'medical_exam': 'yes',
        'report_of_compliance': 'yes',
        'student_personnel_ratio': '145:3',
      },
    if (remarks != null) 'sds_review': {'overall_remarks': remarks},
  };

  /// A proposal the server holds at version 3 ([served]), waiting on the SDS
  /// Office. A decision is answered with the proposal one version on, unless
  /// [conflict] says someone else got there first. [requests] holds what was
  /// sent after the load.
  Future<SapForm> loaded({bool cleared = true}) async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return json(
            proposal(servedState, version: served, cleared: cleared),
          );
        }
        await hold?.future;
        if (conflict) {
          return json({'detail': 'Someone else changed this proposal.'}, 409);
        }
        final rejected = request.url.path.endsWith('/sds-reject');
        return json(
          proposal(
            rejected ? 'rejected' : 'revision_requested',
            version: 4,
            cleared: cleared,
          ),
        );
      }),
    );
    final form = SapForm(eventId: 'e1', service: SapService(client));
    await form.load();
    expect(form.state, SapState.pendingReview);
    expect(form.version, 3);
    requests.clear();
    return form;
  }

  Widget host(Widget home, {UserRole? role}) {
    // The spinner a busy button shows reads the settings.
    final app = ChangeNotifierProvider(
      create: (_) => AppSettings(),
      child: MaterialApp(theme: AppTheme.light(), home: home),
    );
    return role == null
        ? app
        : ChangeNotifierProvider.value(
            value: AppState()..enterDemo(role: role),
            child: app,
          );
  }

  /// The review screen, pushed from a page of its own so that leaving it has
  /// somewhere to go.
  Future<void> open(WidgetTester tester, SapForm form) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SdsSignScreen(form: form),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The text field under the mono label [label] (the label is upper-cased).
  Finder field(String label) => find.descendant(
    of: find.widgetWithText(BrutTextField, label),
    matching: find.byType(TextField),
  );

  /// One stroke on the signature pad, enough to be sent.
  Future<void> draw(WidgetTester tester) async {
    await tester.dragFrom(
      tester.getTopLeft(find.byType(SapSignaturePad)) + const Offset(40, 60),
      const Offset(50, 30),
    );
    await tester.pumpAndSettle();
  }

  Future<void> write(WidgetTester tester, String label, String text) async {
    await tester.enterText(field(label), text);
    await tester.pump();
  }

  bool pressable(WidgetTester tester, String label) => tester
      .widget<BrutButton>(find.widgetWithText(BrutButton, label))
      .onPressed !=
      null;

  /// Taps [button], then [confirm] in the dialog that opens.
  Future<void> decide(
    WidgetTester tester,
    String button, {
    String? confirm,
  }) async {
    await tester.tap(find.widgetWithText(BrutButton, button));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, confirm ?? button));
    await tester.pumpAndSettle();
  }

  group('the screen', () {
    testWidgets('returning needs the overall remark', (tester) async {
      await open(tester, await loaded());

      for (final label in ['Return for revision', 'Reject']) {
        expect(pressable(tester, label), isFalse, reason: label);
      }
      expect(find.textContaining('needs an overall remark'), findsOneWidget);
      expect(find.textContaining('copy with comments'), findsOneWidget);
      expect(find.textContaining('prints on the form'), findsNothing);

      await write(tester, 'OVERALL', 'Move it to the afternoon.');

      for (final label in ['Return for revision', 'Reject']) {
        expect(pressable(tester, label), isTrue, reason: label);
      }
      expect(find.textContaining('needs an overall remark'), findsNothing);
    });

    testWidgets('a blank remark does not count', (tester) async {
      await open(tester, await loaded());

      await write(tester, 'OVERALL', '   ');

      expect(pressable(tester, 'Return for revision'), isFalse);
      expect(pressable(tester, 'Reject'), isFalse);
    });

    testWidgets('stops typing where the server would refuse', (tester) async {
      await open(tester, await loaded());

      expect(tester.widget<TextField>(field('OVERALL')).maxLength, 3000);
      for (final section in SapRemarkSection.values) {
        expect(
          tester
              .widget<TextField>(field(section.label.toUpperCase()))
              .maxLength,
          1000,
          reason: section.wireName,
        );
      }
    });

    testWidgets('returning sends the remarks and the section remarks', (
      tester,
    ) async {
      await open(tester, await loaded());
      await write(tester, 'OVERALL', 'Move it to the afternoon.');
      await write(tester, 'BUDGET', 'Split the venue cost.');

      await tester.tap(find.widgetWithText(BrutButton, 'Return for revision'));
      await tester.pumpAndSettle();

      expect(find.text('Return for revision?'), findsOneWidget);
      expect(find.textContaining('through the Moderator and Dean'), findsOneWidget);
      expect(requests, isEmpty, reason: 'nothing goes before it is confirmed');

      await tester.tap(find.widgetWithText(TextButton, 'Return'));
      await tester.pumpAndSettle();

      final post = requests.single;
      expect(post.method, 'POST');
      expect(post.url.path, '/events/e1/sap-proposal/return');
      expect(jsonDecode(post.body), {
        'expected_version': 3,
        'remarks': 'Move it to the afternoon.',
        'section_remarks': {'budget': 'Split the venue cost.'},
      });
      expect(find.text('Returned for revision.'), findsOneWidget);
      expect(find.byType(SdsSignScreen), findsNothing);
    });

    testWidgets('rejecting is final and says so', (tester) async {
      await open(tester, await loaded());
      await write(tester, 'OVERALL', 'This is not a SAP activity.');
      await write(tester, 'OTHER', 'Belongs to the college office.');

      await tester.tap(find.widgetWithText(BrutButton, 'Reject'));
      await tester.pumpAndSettle();

      expect(find.text('Reject this proposal?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('final'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('copy with comments'), findsOneWidget);
      expect(find.textContaining('print on the form'), findsNothing);
      expect(requests, isEmpty, reason: 'nothing goes before it is confirmed');

      await tester.tap(find.widgetWithText(TextButton, 'Reject'));
      await tester.pumpAndSettle();

      final post = requests.single;
      expect(post.method, 'POST');
      expect(post.url.path, '/events/e1/sap-proposal/sds-reject');
      expect(jsonDecode(post.body), {
        'expected_version': 3,
        'remarks': 'This is not a SAP activity.',
        'section_remarks': {'other': 'Belongs to the college office.'},
      });
      expect(
        find.text('Rejected. The organization has been told.'),
        findsOneWidget,
      );
      expect(find.byType(SdsSignScreen), findsNothing);
    });

    testWidgets('cancelling sends nothing', (tester) async {
      final form = await loaded();
      await open(tester, form);
      await write(tester, 'OVERALL', 'Move it to the afternoon.');

      for (final label in ['Return for revision', 'Reject']) {
        await tester.tap(find.widgetWithText(BrutButton, label));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget, reason: label);

        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing, reason: label);
        expect(requests, isEmpty, reason: label);
      }
      expect(find.byType(SdsSignScreen), findsOneWidget);
      expect(form.state, SapState.pendingReview);
    });

    testWidgets('a changed proposal says so and waits for a reload', (
      tester,
    ) async {
      conflict = true;
      final form = await loaded();
      await open(tester, form);
      await write(tester, 'OVERALL', 'Move it to the afternoon.');
      await draw(tester);
      expect(pressable(tester, 'Approve and sign'), isTrue);
      expect(find.textContaining('Reload it'), findsNothing);

      await decide(tester, 'Return for revision', confirm: 'Return');

      expect(requests, hasLength(1));
      expect(
        find.text('Someone else changed this proposal.'),
        findsOneWidget,
        reason: 'the snackbar carries the words the server sent',
      );
      expect(find.byType(SdsSignScreen), findsOneWidget);
      expect(form.isStale, isTrue);
      expect(form.state, SapState.pendingReview);

      // The way on is named, and nothing can be sent until it is taken: every
      // request would carry the old version and be refused again.
      final banner = tester.widget<BrutInlineMessage>(
        find.byWidgetPredicate(
          (w) => w is BrutInlineMessage && w.text.contains('Reload it'),
        ),
      );
      expect(banner.tone, BrutTone.coral);
      expect(banner.icon, Icons.sync_problem);
      expect(banner.text, contains('Someone else changed this proposal.'));
      for (final label in [
        'Return for revision',
        'Reject',
        'Approve and sign',
        'Save remarks',
      ]) {
        expect(pressable(tester, label), isFalse, reason: label);
      }
      expect(pressable(tester, 'Reload the proposal'), isTrue);
      expect(find.text('Move it to the afternoon.'), findsOneWidget);

      // Meanwhile the proposal moved on a version, and is still waiting.
      conflict = false;
      served = 4;
      requests.clear();
      await tester.tap(find.widgetWithText(BrutButton, 'Reload the proposal'));
      await tester.pumpAndSettle();

      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/events/e1/sap-proposal');
      expect(form.isStale, isFalse);
      expect(form.version, 4);
      expect(find.textContaining('Reload it'), findsNothing);
      expect(find.text('Reload the proposal'), findsNothing);
      expect(find.text('Move it to the afternoon.'), findsOneWidget);
      for (final label in ['Return for revision', 'Reject', 'Approve and sign']) {
        expect(pressable(tester, label), isTrue, reason: label);
      }

      await decide(tester, 'Return for revision', confirm: 'Return');

      final post = requests.last;
      expect(post.method, 'POST');
      expect(post.url.path, '/events/e1/sap-proposal/return');
      expect(jsonDecode(post.body), {
        'expected_version': 4,
        'remarks': 'Move it to the afternoon.',
        'section_remarks': <String, dynamic>{},
      });
      expect(find.byType(SdsSignScreen), findsNothing);
    });

    testWidgets('a reload that finds the proposal decided locks the screen', (
      tester,
    ) async {
      conflict = true;
      final form = await loaded();
      await open(tester, form);
      await write(tester, 'OVERALL', 'Move it to the afternoon.');
      await decide(tester, 'Return for revision', confirm: 'Return');
      expect(form.isStale, isTrue);

      // Someone else got there first and signed it.
      conflict = false;
      served = 4;
      servedState = 'sds_signed';
      await tester.tap(find.widgetWithText(BrutButton, 'Reload the proposal'));
      await tester.pumpAndSettle();

      expect(form.isStale, isFalse);
      expect(find.textContaining('Reload it'), findsNothing);
      expect(find.text('This revision is signed and locked.'), findsOneWidget);
      expect(find.textContaining('Return it'), findsNothing);
      expect(pressable(tester, 'Return for revision'), isFalse);
      expect(pressable(tester, 'Reject'), isFalse);
      expect(find.text('Move it to the afternoon.'), findsOneWidget);
    });

    testWidgets('only the button that was pressed shows busy', (tester) async {
      hold = Completer<void>();
      await open(tester, await loaded());
      await write(tester, 'OVERALL', 'Move it to the afternoon.');
      await draw(tester);

      await tester.tap(find.widgetWithText(BrutButton, 'Return for revision'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Return'));
      // The spinner never settles, so step by hand.
      await tester.pump(const Duration(milliseconds: 300));

      expect(requests, hasLength(1));
      expect(find.text('Returning'), findsOneWidget);
      expect(find.text('Signing'), findsNothing);
      expect(find.text('Rejecting'), findsNothing);
      expect(find.text('Saving'), findsNothing);
      // Not busy, but not to be pressed either while the request is out.
      for (final label in ['Approve and sign', 'Reject', 'Save remarks']) {
        expect(pressable(tester, label), isFalse, reason: label);
      }

      hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SdsSignScreen), findsNothing);
    });

    testWidgets('and signing is the one that says Signing', (tester) async {
      hold = Completer<void>();
      await open(tester, await loaded());
      await write(tester, 'OVERALL', 'Move it to the afternoon.');
      await draw(tester);

      await tester.tap(find.widgetWithText(BrutButton, 'Approve and sign'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Sign'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(requests.single.url.path, endsWith('/sds-sign'));
      expect(find.text('Signing'), findsOneWidget);
      expect(find.text('Returning'), findsNothing);
      expect(find.text('Rejecting'), findsNothing);

      hold!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('returning does not wait for Part 4', (tester) async {
      await open(tester, await loaded(cleared: false));
      await write(tester, 'OVERALL', 'Move it to the afternoon.');

      expect(pressable(tester, 'Return for revision'), isTrue);
      expect(pressable(tester, 'Reject'), isTrue);
      expect(pressable(tester, 'Approve and sign'), isFalse);

      await decide(tester, 'Return for revision', confirm: 'Return');

      expect(requests.single.url.path, endsWith('/return'));
      expect(find.byType(SdsSignScreen), findsNothing);
    });

    testWidgets('signing still needs Part 4, and a drawing', (tester) async {
      await open(tester, await loaded(cleared: false));

      expect(pressable(tester, 'Approve and sign'), isFalse);
      expect(find.textContaining('Confirm Part 4'), findsOneWidget);
    });

    testWidgets('a signed revision cannot be returned or rejected', (
      tester,
    ) async {
      final form = SapForm(eventId: 'e1')
        ..seedLocally(state: SapState.sdsSigned, sdsRemarks: 'Signed already.');
      await open(tester, form);

      expect(pressable(tester, 'Return for revision'), isFalse);
      expect(pressable(tester, 'Reject'), isFalse);
    });

    testWidgets('is called Review and decide', (tester) async {
      await open(tester, await loaded());

      expect(find.text('Review and decide'), findsOneWidget);
      expect(find.text('Review and sign'), findsNothing);
      expect(find.text('Sign the proposal'), findsNothing);
    });
  });

  group('the form', () {
    const refusal =
        'Write the overall remark first: it is the reason the organization '
        'reads.';

    Future<String?> sdsReturn(SapForm form) => form.sdsReturn();
    Future<String?> sdsReject(SapForm form) => form.sdsReject();

    test('refuses a blank remark without asking the server', () async {
      for (final decision in [sdsReturn, sdsReject]) {
        for (final blank in ['', '  \n ']) {
          final form = await loaded();
          form.overallRemarks = blank;

          expect(await decision(form), refusal);
          expect(requests, isEmpty);
          expect(form.state, SapState.pendingReview);
        }
      }
    });

    test('with no server says what signing says', () async {
      final form = SapForm(eventId: 'e1')
        ..overallRemarks = 'Move it to the afternoon.';

      expect(
        await sdsReturn(form),
        'This proposal has not been saved to the server yet.',
      );
      expect(
        await sdsReject(form),
        'This proposal has not been saved to the server yet.',
      );
    });

    test('adopts the proposal the server answers with', () async {
      final form = await loaded();
      form.overallRemarks = ' Move it to the afternoon. ';

      expect(await sdsReturn(form), isNull);

      expect(form.state, SapState.revisionRequested);
      expect(form.version, 4);
      expect(
        jsonDecode(requests.single.body)['remarks'],
        'Move it to the afternoon.',
      );
    });

    test('gives back the server\'s reason when it refuses', () async {
      conflict = true;
      final form = await loaded();
      form.overallRemarks = 'Move it to the afternoon.';

      expect(await sdsReject(form), 'Someone else changed this proposal.');
      expect(form.isStale, isTrue);
      expect(form.saving, isFalse);
    });
  });

  group('the hub', () {
    testWidgets('sends the SDS Office to one screen, not two buttons', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 3000);
      addTearDown(tester.view.reset);
      final form = SapForm(eventId: 'e1')
        ..seedLocally(state: SapState.pendingReview);

      await tester.pumpWidget(
        host(SapFormScreen(form: form), role: UserRole.sdsStaff),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Review and decide'), findsOneWidget);
      expect(find.text('Return for revision'), findsNothing);
    });
  });
}
