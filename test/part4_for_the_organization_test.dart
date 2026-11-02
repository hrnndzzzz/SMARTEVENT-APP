import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/api/sap_service.dart';
import 'package:smartevent/screens/sap/sap_form_fields.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/screens/sap/sap_part4_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// Part 4 is the SDS Office's own section. The server takes it from SDS
/// staff alone, and only while the proposal is with them.
///
/// The screens asked nothing but whether the session could write, which is
/// an offline flag and not a role: any account could open Part 4 and press
/// "Confirm clearance", and any account saw "Review and decide" on a proposal
/// waiting on the office. The organization now reads Part 4 instead, with
/// where the proposal is and what the office said.
void main() {
  /// [role] is whose account is signed in; none hosts no [AppState] at all.
  Widget host(Widget home, {UserRole? role}) {
    final app = MaterialApp(theme: AppTheme.light(), home: home);
    return role == null
        ? app
        : ChangeNotifierProvider.value(
            value: AppState()..enterDemo(role: role),
            child: app,
          );
  }

  Future<void> open(WidgetTester tester, Widget home, {UserRole? role}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 3000);
    addTearDown(tester.view.reset);
    // A fresh tree each time: a screen of the same type keeps its state, and
    // with it the form it first opened on, so a loop would read the first.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(home, role: role));
    await tester.pump(const Duration(milliseconds: 300));
  }

  http.Response json(Map<String, dynamic> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  /// What the SDS Office recorded in Part 4. None of it is what the screen
  /// seeds when nothing is recorded, or the hint under an empty field, so
  /// each can be told apart by the text it puts on screen.
  const recorded = <String, dynamic>{
    'parents_consent': 'yes',
    'attachments': 'Letter of invitation and budget',
    'class_interruption': 'none',
    'medical_exam': 'not_applicable',
    'medical_exam_reason': 'No medical exam is needed',
    'report_of_compliance': 'not_applicable',
    'report_of_compliance_reason': 'Stays on campus',
    'student_personnel_ratio': '120:4',
  };

  /// A proposal the server holds in [state], loaded; with Part 4 [confirmed]
  /// when the office has recorded its clearance. [readOnly] is the session
  /// losing the right to write after that, as when it goes offline: a client
  /// that cannot write cannot fetch the proposal in the first place.
  Future<SapForm> loaded(
    String state, {
    Map<String, dynamic> extra = const {},
    bool confirmed = false,
    bool readOnly = false,
  }) async {
    final client = ApiClient(
      httpClient: MockClient(
        (_) async => json({
          'id': 'p1',
          'event_id': 'e1',
          'state': state,
          'version': 4,
          'revision_no': 1,
          'details': {'title': 'Hack the Future'},
          'collections': <String, dynamic>{},
          if (confirmed) 'clearance': recorded,
          ...extra,
        }),
      ),
    );
    final form = SapForm(eventId: 'e1', service: SapService(client));
    await form.load();
    // A form that never loaded holds no proposal, and reads as locked to
    // whoever opens it.
    expect(form.state, SapState.fromWire(state));
    client.readOnly = readOnly;
    return form;
  }

  /// Whether each answer the screen offers can be changed.
  List<bool> offered(WidgetTester tester) => [
    for (final field in tester.widgetList<BrutTextField>(
      find.byType(BrutTextField),
    ))
      field.enabled,
    for (final choice in tester.widgetList<SapSingleChoice<SapClearanceAnswer>>(
      find.byType(SapSingleChoice<SapClearanceAnswer>),
    ))
      choice.enabled,
  ];

  BrutButton confirm(WidgetTester tester) => tester.widget<BrutButton>(
    find.widgetWithText(BrutButton, 'Confirm clearance'),
  );

  /// The card that says where Part 4 is, found by what it says.
  BrutCard card(WidgetTester tester, String line) => tester.widget<BrutCard>(
    find.ancestor(of: find.text(line), matching: find.byType(BrutCard)),
  );

  void expectRead(WidgetTester tester, {String? reason}) {
    expect(
      offered(tester),
      allOf(isNotEmpty, everyElement(isFalse)),
      reason: reason,
    );
    expect(confirm(tester).onPressed, isNull, reason: reason);
  }

  group('Part 4 for an organization', () {
    testWidgets('is read, with the SDS Office\'s card above the answers', (
      tester,
    ) async {
      final form = await loaded('pending_sap_review', confirmed: true);
      await open(tester, SapPart4Screen(form: form), role: UserRole.treasurer);

      expectRead(tester);
      expect(card(tester, 'With the SDS Office').tone, BrutTone.sun);
    });

    testWidgets('shows what the office recorded, not what it seeds', (
      tester,
    ) async {
      final form = await loaded('pending_sap_review', confirmed: true);
      await open(tester, SapPart4Screen(form: form), role: UserRole.treasurer);

      expect(
        tester
            .widgetList<SapSingleChoice<SapClearanceAnswer>>(
              find.byType(SapSingleChoice<SapClearanceAnswer>),
            )
            .map((choice) => choice.value),
        [
          SapClearanceAnswer.yes,
          SapClearanceAnswer.none,
          SapClearanceAnswer.notApplicable,
          SapClearanceAnswer.notApplicable,
        ],
      );
      for (final said in [
        'Letter of invitation and budget',
        'No medical exam is needed',
        'Stays on campus',
        '120:4',
      ]) {
        expect(find.text(said), findsOneWidget);
      }
      expectRead(tester);
    });

    testWidgets('leaves the answers out when none has been recorded', (
      tester,
    ) async {
      // The screen seeds "Not applicable" with no reason, which the server
      // would refuse and which reads as the office's own answer once the card
      // says it has acted. Nobody who cannot fill it in is shown that.
      for (final role in [UserRole.treasurer, UserRole.sdsStaff]) {
        for (final state in SapState.values) {
          // Theirs to fill in, and the seeds are where they start.
          if (role == UserRole.sdsStaff && state == SapState.pendingReview) {
            continue;
          }
          final form = await loaded(state.wireName);
          await open(tester, SapPart4Screen(form: form), role: role);

          final reason = '${role.name} at ${state.wireName}';
          expect(find.byType(BrutTextField), findsNothing, reason: reason);
          expect(
            find.byType(SapSingleChoice<SapClearanceAnswer>),
            findsNothing,
            reason: reason,
          );
          // What is left still says where it stands.
          expect(find.byType(BrutCard), findsOneWidget, reason: reason);
          expect(confirm(tester).onPressed, isNull, reason: reason);
        }
      }
    });

    testWidgets('is read by every account that is not the SDS Office', (
      tester,
    ) async {
      for (final role in UserRole.values) {
        if (role == UserRole.sdsStaff) continue;
        final form = await loaded('pending_sap_review', confirmed: true);
        await open(tester, SapPart4Screen(form: form), role: role);
        expectRead(tester, reason: role.name);
      }
    });

    testWidgets('is read when there is no account to ask', (tester) async {
      // Nobody is taken for the office on a hunch.
      final form = await loaded('pending_sap_review', confirmed: true);
      await open(tester, SapPart4Screen(form: form));

      expectRead(tester);
    });

    testWidgets('says where the proposal is, whatever the state', (
      tester,
    ) async {
      for (final (wire, by, line, tone) in [
        (
          'pending_department_review',
          null,
          'With the Moderator and Dean',
          BrutTone.sun,
        ),
        ('pending_sap_review', null, 'With the SDS Office', BrutTone.sun),
        ('revision_requested', 'sds', 'Needs revision', BrutTone.coral),
        // Only the SDS Office could return one before the department could,
        // and an older server still does not say who.
        ('revision_requested', null, 'Needs revision', BrutTone.coral),
        ('sds_signed', null, 'Approved', BrutTone.mint),
        ('approved', null, 'Approved', BrutTone.mint),
        ('completed', null, 'Approved', BrutTone.mint),
        ('rejected', null, 'Rejected', BrutTone.coral),
      ]) {
        final form = await loaded(wire, extra: {'returned_by': ?by});
        await open(
          tester,
          SapPart4Screen(form: form),
          role: UserRole.treasurer,
        );
        expect(card(tester, line).tone, tone, reason: '$wire returned by $by');
      }
    });

    testWidgets('does not call a proposal the SDS Office has not had its own', (
      tester,
    ) async {
      for (final (wire, extra) in <(String, Map<String, dynamic>)>[
        ('draft', {}),
        (
          'revision_requested',
          {'returned_by': 'moderator', 'return_remarks': 'Cut the budget'},
        ),
        (
          'revision_requested',
          {'returned_by': 'dean', 'return_remarks': 'Cut the budget'},
        ),
      ]) {
        final form = await loaded(wire, extra: extra);
        await open(
          tester,
          SapPart4Screen(form: form),
          role: UserRole.treasurer,
        );

        final reason = '$wire $extra';
        expect(find.text('Needs revision'), findsNothing, reason: reason);
        expect(find.text('With the SDS Office'), findsNothing, reason: reason);
        // The Moderator's or Dean's reason is theirs, not the office's.
        expect(
          find.textContaining('Cut the budget'),
          findsNothing,
          reason: reason,
        );
        expect(
          card(tester, 'Not with the SDS Office yet').tone,
          BrutTone.neutral,
          reason: reason,
        );
      }
    });

    testWidgets('lists what the SDS Office said, with its section labels', (
      tester,
    ) async {
      // A signed proposal always has its clearance.
      final form = await loaded(
        'sds_signed',
        confirmed: true,
        extra: {
          'sds_review': {
            'overall_remarks': 'Fine, with a note on the food budget.',
            'section_remarks': {
              'clearance': 'Class interruption confirmed.',
              'budget': 'Meals are over the allowance.',
            },
          },
        },
      );
      await open(tester, SapPart4Screen(form: form), role: UserRole.treasurer);

      final said = tester.widget<BrutInlineMessage>(
        find.byWidgetPredicate(
          (w) => w is BrutInlineMessage && w.text.contains('Meals are over'),
        ),
      );
      // The overall remark first, then each section in the form's order.
      expect(
        said.text,
        'Fine, with a note on the food budget.\n'
        'Budget: Meals are over the allowance.\n'
        'Clearance: Class interruption confirmed.',
      );
      expect(find.text('No remarks from the SDS Office yet.'), findsNothing);
    });

    testWidgets('says so when the SDS Office has said nothing yet', (
      tester,
    ) async {
      final form = await loaded('pending_sap_review');
      await open(tester, SapPart4Screen(form: form), role: UserRole.treasurer);

      expect(find.text('No remarks from the SDS Office yet.'), findsOneWidget);
    });

    testWidgets('does not say "yet" once the office has signed', (
      tester,
    ) async {
      // Nothing more comes from the office after it signs, so "yet" promised
      // remarks that cannot arrive.
      for (final wire in ['sds_signed', 'approved', 'completed']) {
        final form = await loaded(wire, confirmed: true);
        await open(
          tester,
          SapPart4Screen(form: form),
          role: UserRole.treasurer,
        );

        expect(
          find.text('The SDS Office left no remarks.'),
          findsOneWidget,
          reason: wire,
        );
        expect(find.textContaining('yet'), findsNothing, reason: wire);
      }
    });
  });

  group('Part 4 for the SDS Office', () {
    testWidgets('is theirs to fill in while the proposal is with them', (
      tester,
    ) async {
      // Nothing recorded yet: the seeds are where they start.
      final form = await loaded('pending_sap_review');
      await open(tester, SapPart4Screen(form: form), role: UserRole.sdsStaff);

      expect(offered(tester), allOf(isNotEmpty, everyElement(isTrue)));
      expect(confirm(tester).onPressed, isNotNull);
      // They are the ones to decide, so there is no outcome to read.
      expect(find.text('With the SDS Office'), findsNothing);
      expect(find.text('No remarks from the SDS Office yet.'), findsNothing);
    });

    testWidgets('is only read at any other point in the proposal', (
      tester,
    ) async {
      for (final state in SapState.values) {
        if (state == SapState.pendingReview) continue;
        final form = await loaded(state.wireName, confirmed: true);
        await open(tester, SapPart4Screen(form: form), role: UserRole.sdsStaff);
        expectRead(tester, reason: state.wireName);
      }
    });

    testWidgets('is only read on a session that cannot write', (tester) async {
      final form = await loaded(
        'pending_sap_review',
        confirmed: true,
        readOnly: true,
      );
      await open(tester, SapPart4Screen(form: form), role: UserRole.sdsStaff);

      expect(form.isReadOnly, isTrue);
      expectRead(tester);
    });
  });

  group('the hub', () {
    SapForm waiting() =>
        SapForm(eventId: 'e1')..seedLocally(state: SapState.pendingReview);

    testWidgets('offers the SDS Office its review, and only that', (
      tester,
    ) async {
      await open(
        tester,
        SapFormScreen(form: waiting()),
        role: UserRole.sdsStaff,
      );

      expect(find.text('SDS Office'), findsOneWidget);
      expect(find.text('Review and decide'), findsOneWidget);
      // Returning and rejecting are decided on the review screen.
      expect(find.text('Return for revision'), findsNothing);
    });

    testWidgets('offers nobody else either', (tester) async {
      for (final role in UserRole.values) {
        if (role == UserRole.sdsStaff) continue;
        await open(tester, SapFormScreen(form: waiting()), role: role);

        expect(find.text('SDS Office'), findsNothing, reason: role.name);
        expect(find.text('Review and decide'), findsNothing, reason: role.name);
        expect(
          find.text('Return for revision'),
          findsNothing,
          reason: role.name,
        );
      }
    });

    testWidgets('offers nothing when there is no account to ask', (
      tester,
    ) async {
      await open(tester, SapFormScreen(form: waiting()));

      expect(find.text('Review and decide'), findsNothing);
      expect(find.text('Return for revision'), findsNothing);
    });
  });
}
