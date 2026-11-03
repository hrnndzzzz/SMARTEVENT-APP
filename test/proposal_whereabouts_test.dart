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
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/screens/sap/sap_part3_screen.dart';
import 'package:smartevent/screens/sap/sap_proposal_flow.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart' show AppState, UserRole;
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// Where the organization's proposal is, and whose words it is reading.
///
/// Sending a proposal now sends it to the Moderator and the Dean, and
/// either can send it back. A proposal they still had read as nothing in
/// particular, one they returned said the SDS Office had, and a rejection
/// looked like any other return.
void main() {
  Widget host(Widget home) => ChangeNotifierProvider(
    create: (_) => AppSettings(),
    child: MaterialApp(theme: AppTheme.light(), home: home),
  );

  Map<String, dynamic> aggregate(
    String state, [
    Map<String, dynamic> extra = const {},
  ]) => {
    'id': 'p1',
    'event_id': 'e1',
    'state': state,
    'version': 4,
    'revision_no': 1,
    'details': {'title': 'Hack the Future'},
    'collections': <String, dynamic>{},
    ...extra,
  };

  SapForm formFor(MockClient client) => SapForm(
    eventId: 'e1',
    service: SapService(ApiClient(httpClient: client)),
  );

  http.Response json(Map<String, dynamic> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  /// A proposal the server holds in [state], loaded.
  Future<SapForm> loaded(
    String state, [
    Map<String, dynamic> extra = const {},
  ]) async {
    final form = formFor(
      MockClient((_) async => json(aggregate(state, extra))),
    );
    await form.load();
    return form;
  }

  /// The hub, as [role] when one is given and as nobody in particular when
  /// not.
  Future<void> openHub(
    WidgetTester tester,
    SapForm form, {
    UserRole? role,
  }) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final hub = host(SapFormScreen(form: form));
    await tester.pumpWidget(
      role == null
          ? hub
          : ChangeNotifierProvider.value(
              value: AppState()..enterDemo(role: role),
              child: hub,
            ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The one banner whose text has [containing] in it.
  BrutInlineMessage banner(WidgetTester tester, String containing) =>
      tester.widget<BrutInlineMessage>(
        find.byWidgetPredicate(
          (w) => w is BrutInlineMessage && w.text.contains(containing),
        ),
      );

  group('the hub', () {
    testWidgets('says the Moderator and Dean have it, not the SDS Office', (
      tester,
    ) async {
      // A stale return left on it must not show: the server clears it on
      // resubmission, and the app reads it only for a returned proposal.
      final form = await loaded('pending_department_review', {
        'returned_by': 'dean',
        'return_remarks': 'Cut the budget',
      });
      await openHub(tester, form);

      final notice = banner(tester, 'With the Moderator and Dean');
      expect(notice.text, contains('before it goes to the SDS Office'));
      expect(notice.tone, BrutTone.sun);
      expect(notice.icon, Icons.hourglass_top);
      expect(find.textContaining('SDS Office sent'), findsNothing);
      expect(find.textContaining('Returned by'), findsNothing);
      expect(find.textContaining('Cut the budget'), findsNothing);
    });

    testWidgets('keeps Part 5 shut while the department has it', (
      tester,
    ) async {
      // Nothing in Part 5 can happen until the SDS Office has the paper.
      await openHub(tester, await loaded('pending_department_review'));

      final part5 = find.widgetWithText(BrutListRow, 'University Clearance');
      expect(
        find.descendant(of: part5, matching: find.text('Not yet')),
        findsOneWidget,
      );
      expect(tester.widget<BrutListRow>(part5).onTap, isNull);
    });

    testWidgets('names the Moderator or the Dean who sent it back', (
      tester,
    ) async {
      for (final (wire, who) in [
        ('moderator', 'the Moderator'),
        ('dean', 'the Dean'),
      ]) {
        final form = await loaded('revision_requested', {
          'returned_by': wire,
          'return_remarks': 'Move it to the afternoon',
        });
        await openHub(tester, form);

        final notice = banner(tester, 'Returned by');
        expect(notice.text, contains('Returned by $who'), reason: wire);
        expect(notice.text, contains('Move it to the afternoon'), reason: wire);
        expect(notice.tone, BrutTone.coral);
        expect(
          find.textContaining('SDS Office sent'),
          findsNothing,
          reason: wire,
        );
      }
    });

    testWidgets('lists the SDS Office\'s remarks by section under its return', (
      tester,
    ) async {
      final form = await loaded('revision_requested', {
        'returned_by': 'sds',
        'return_remarks': 'Fix the budget',
        'sds_review': {
          'overall_remarks': 'Fix the budget',
          'section_remarks': {'budget': 'Meals over the allowance'},
        },
      });
      await openHub(tester, form);

      final notice = banner(tester, 'Returned by the SDS Office');
      expect(notice.text, contains('Fix the budget'));
      expect(notice.text, contains('Budget: Meals over the allowance'));
    });

    testWidgets('does not put the SDS Office\'s remarks under the Dean\'s', (
      tester,
    ) async {
      final form = await loaded('revision_requested', {
        'returned_by': 'dean',
        'return_remarks': 'Move it to the afternoon',
        'sds_review': {
          'section_remarks': {'budget': 'Meals over the allowance'},
        },
      });
      await openHub(tester, form);

      expect(find.textContaining('Returned by the Dean'), findsOneWidget);
      expect(find.textContaining('Meals over the allowance'), findsNothing);
    });

    testWidgets('reads a rejection as final, with the office\'s reasons', (
      tester,
    ) async {
      // The leftover return is not shown: a rejection is not a return.
      final form = await loaded('rejected', {
        'returned_by': 'dean',
        'return_remarks': 'Cut the budget',
        'sds_review': {
          'overall_remarks': 'Not an organizational activity',
          'section_remarks': {'budget': 'Meals over the allowance'},
        },
      });
      await openHub(tester, form);

      final notice = banner(tester, 'Rejected by the SDS Office');
      expect(notice.text, contains('final'));
      expect(notice.text, contains('start a new one'));
      expect(notice.text, contains('Not an organizational activity'));
      expect(notice.text, contains('Budget: Meals over the allowance'));
      expect(notice.tone, BrutTone.coral);
      expect(notice.icon, Icons.block);

      expect(find.textContaining('Returned by'), findsNothing);
      expect(find.textContaining('sent this back'), findsNothing);
      expect(find.textContaining('Cut the budget'), findsNothing);
      expect(
        tester
            .widget<BrutButton>(
              find.widgetWithText(BrutButton, 'Submit for review'),
            )
            .onPressed,
        isNull,
        reason: 'nothing can be sent again',
      );
    });

    testWidgets('says a rejection is final even with no remarks to show', (
      tester,
    ) async {
      await openHub(tester, await loaded('rejected'));

      expect(
        banner(tester, 'Rejected by the SDS Office').text,
        'Rejected by the SDS Office. This proposal is final; start a new '
        'one to try again.',
      );
    });

    testWidgets('says sending it went for department review', (tester) async {
      final client = MockClient((request) async {
        final sent =
            request.method == 'POST' && request.url.path.endsWith('/submit');
        return json(
          sent
              ? aggregate('pending_department_review', {'version': 5})
              : aggregate('draft'),
        );
      });
      final form = formFor(client);
      await form.load();
      await openHub(tester, form);

      await tester.tap(find.text('Submit for review'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Sent for department review.'), findsOneWidget);
      expect(find.textContaining('nine signatures'), findsNothing);
      expect(form.state, SapState.pendingDepartmentReview);
    });

    // The demo has no server and seeds the state it wants shown. A form with
    // no service counts as local, and local used to mean editable whatever
    // the state said, so a seeded rejected or department-review proposal
    // still offered "Submit for review".
    group('with no server', () {
      Future<bool> canSubmit(WidgetTester tester, SapForm form) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await openHub(tester, form);
        final submit = find.widgetWithText(BrutButton, 'Submit for review');
        return tester.widget<BrutButton>(submit).onPressed != null;
      }

      testWidgets('offers sending only what is a draft or was returned', (
        tester,
      ) async {
        for (final state in SapState.values) {
          final form = SapForm(eventId: 'e1')..seedLocally(state: state);

          expect(
            await canSubmit(tester, form),
            state.isProposerEditable,
            reason: state.name,
          );
        }
      });

      testWidgets('and keeps a proposal that has no state yet editable', (
        tester,
      ) async {
        expect(await canSubmit(tester, SapForm()), isTrue, reason: 'brand new');
        expect(
          await canSubmit(tester, SapForm(eventId: 'e1')),
          isTrue,
          reason: 'an event the demo does not seed',
        );
      });
    });
  });

  // The hub and the status card are read by the proposer, by the Moderator
  // and the Dean, and by the SDS Office. Each of them used to be told the
  // proposer's version: "your" Moderator, "start a new one", "nothing more is
  // needed from you".
  group('the hub, read by each role', () {
    testWidgets('says the Moderator and Dean have it, to everyone', (
      tester,
    ) async {
      for (final role in [null, UserRole.sdsStaff]) {
        final form = await loaded('pending_department_review');
        await tester.pumpWidget(const SizedBox.shrink());
        await openHub(tester, form, role: role);

        final notice = banner(tester, 'With the Moderator and Dean');
        expect(
          notice.text,
          'With the Moderator and Dean. They approve it before it goes to '
          'the SDS Office.',
          reason: '$role',
        );
        expect(notice.tone, BrutTone.sun, reason: '$role');
        expect(notice.icon, Icons.hourglass_top, reason: '$role');
        expect(find.textContaining('your Moderator'), findsNothing);
      }
    });

    testWidgets('tells the SDS Office a rejection is final, and no more', (
      tester,
    ) async {
      final rejected = {
        'sds_review': {
          'overall_remarks': 'Not an organizational activity',
          'section_remarks': {'budget': 'Meals over the allowance'},
        },
      };

      await openHub(
        tester,
        await loaded('rejected', rejected),
        role: UserRole.sdsStaff,
      );
      final office = banner(tester, 'Rejected by the SDS Office');
      expect(
        office.text,
        'Rejected by the SDS Office. This proposal is final.\n'
        'Not an organizational activity\n'
        'Budget: Meals over the allowance',
      );
      expect(office.tone, BrutTone.coral);
      expect(office.icon, Icons.block);

      // The proposer still reads the advice meant for them.
      await tester.pumpWidget(const SizedBox.shrink());
      await openHub(tester, await loaded('rejected', rejected));
      expect(
        banner(tester, 'Rejected by the SDS Office').text,
        contains('start a new one to try again'),
      );
    });

    testWidgets('tells the SDS Office to record how the activity went', (
      tester,
    ) async {
      await openHub(tester, await loaded('approved'), role: UserRole.sdsStaff);

      final office = banner(tester, 'The activity has run');
      expect(
        office.text,
        'The activity has run. Record how it went in Part 6.',
      );
      expect(office.tone, BrutTone.sun);
      expect(office.icon, Icons.hourglass_top);
      expect(find.textContaining('nothing more is needed'), findsNothing);

      // The proposer is told to wait for the office, as before.
      await tester.pumpWidget(const SizedBox.shrink());
      await openHub(tester, await loaded('approved'));
      expect(
        banner(tester, 'Waiting on the SDS Office').text,
        contains('nothing more is needed from you'),
      );
      expect(find.textContaining('The activity has run'), findsNothing);
    });

    testWidgets(
      'shuts Part 5 after the department\'s return, not the office\'s',
      (tester) async {
        // A Moderator or Dean return sends the paper back before the office
        // has it, so there is nothing in Part 5 to do; the office's own
        // return leaves the clearance it had started.
        for (final (by, shut) in <(String?, bool)>[
          ('moderator', true),
          ('dean', true),
          ('sds', false),
          (null, false),
        ]) {
          final form = await loaded('revision_requested', {'returned_by': ?by});
          await tester.pumpWidget(const SizedBox.shrink());
          await openHub(tester, form);

          final part5 = find.widgetWithText(
            BrutListRow,
            'University Clearance',
          );
          expect(
            find.descendant(of: part5, matching: find.text('Not yet')),
            shut ? findsOneWidget : findsNothing,
            reason: '$by',
          );
          expect(
            tester.widget<BrutListRow>(part5).onTap,
            shut ? isNull : isNotNull,
            reason: '$by',
          );
        }
      },
    );

    // The card and its lock note behind the hub, once it is no longer the
    // proposer's to edit.
    Future<void> show(WidgetTester tester, SapForm form) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(host(SapProposalStatus(form: form)));
      await tester.pumpAndSettle();
    }

    testWidgets('does not say a proposal that never loaded was sent', (
      tester,
    ) async {
      // No reply yet, and then a reply that failed: neither is "Sent".
      final unloaded = formFor(
        MockClient((_) async => http.Response('Server error', 500)),
      );
      final failed = formFor(
        MockClient((_) async => http.Response('Server error', 500)),
      );
      await failed.load();
      expect(failed.state, isNull);
      expect(failed.error, isNotNull);

      await show(tester, unloaded);
      expect(find.text('Not loaded'), findsOneWidget);
      expect(
        find.text('The proposal could not be loaded. Open it again to retry.'),
        findsOneWidget,
      );
      expect(
        tester.widget<BrutCard>(find.byType(BrutCard)).tone,
        BrutTone.neutral,
      );
      expect(find.text('Sent'), findsNothing);
      expect(find.textContaining('Waiting on the SDS Office'), findsNothing);
      expect(find.textContaining('read-only'), findsNothing);

      await show(tester, failed);
      expect(find.text('Not loaded'), findsOneWidget);
      expect(find.text(failed.error!), findsOneWidget);
      expect(find.textContaining('could not be loaded'), findsNothing);
      expect(find.text('Sent'), findsNothing);
    });

    testWidgets('says who signed once the SDS Office has', (tester) async {
      for (final state in [
        SapState.sdsSigned,
        SapState.approved,
        SapState.completed,
      ]) {
        await show(tester, SapForm(eventId: 'e1')..seedLocally(state: state));

        expect(
          find.text(
            'Parts 1 to 3 are locked: the SDS Office has signed this '
            'revision.',
          ),
          findsOneWidget,
          reason: state.name,
        );
        expect(find.textContaining('under review'), findsNothing);
        expect(find.textContaining('returns it'), findsNothing);
      }

      // Still under review, the note is the one it was.
      await show(
        tester,
        SapForm(eventId: 'e1')..seedLocally(state: SapState.pendingReview),
      );
      expect(
        find.textContaining('read-only while it is under review'),
        findsOneWidget,
      );
      expect(find.textContaining('the SDS Office returns it'), findsOneWidget);
    });
  });

  group('the steps', () {
    SapPart3Screen lastStep(SapForm form) =>
        SapPart3Screen(form: form, step: 2, onContinue: (_) async {});

    testWidgets('end on sending it for review', (tester) async {
      await tester.pumpWidget(host(lastStep(SapForm(eventId: 'e1'))));
      await tester.pumpAndSettle();

      expect(find.text('Send for review'), findsOneWidget);
      expect(find.text('Send to the SDS Office'), findsNothing);
    });

    testWidgets('say nothing has been sent when you leave', (tester) async {
      await tester.pumpWidget(host(lastStep(SapForm(eventId: 'e1'))));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Nothing has been sent yet'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('SDS Office'),
        ),
        findsNothing,
      );
    });

    testWidgets('and sending says it went for department review', (
      tester,
    ) async {
      final day = DateTime.now().add(const Duration(days: 60));
      final draft = aggregate('draft', {
        'details': {
          'title': 'Hack the Future',
          'department': 'College of Arts and Sciences',
          'activity_date': day.toIso8601String().substring(0, 10),
          'setting': 'on_campus',
        },
      });
      final client = MockClient((request) async {
        final sent =
            request.method == 'POST' && request.url.path.endsWith('/submit');
        return json(
          sent ? {...draft, 'state': 'pending_department_review'} : draft,
        );
      });
      final form = formFor(client);

      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => SapProposalFlow.start(context, form),
                child: const Text('Open the proposal'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open the proposal'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start the form'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next: school support'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Next:'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send for review'));
      await tester.pumpAndSettle();

      expect(form.state, SapState.pendingDepartmentReview);
      expect(find.text('Sent for department review.'), findsOneWidget);
      expect(find.text('Sent to the SDS Office.'), findsNothing);
    });
  });

  group('the status card', () {
    SapForm seeded(SapState state, {SapReturnedBy? by, String? remarks}) =>
        SapForm(eventId: 'e1')
          ..seedLocally(state: state, returnedBy: by, returnRemarks: remarks);

    BrutTone toneOf(WidgetTester tester) =>
        tester.widget<BrutCard>(find.byType(BrutCard)).tone;

    testWidgets('puts the department\'s proposal with the Moderator and Dean', (
      tester,
    ) async {
      final form = seeded(SapState.pendingDepartmentReview);
      await tester.pumpWidget(host(SapProposalStatus(form: form)));
      await tester.pumpAndSettle();

      expect(find.text('With the Moderator and Dean'), findsOneWidget);
      expect(toneOf(tester), BrutTone.sun);
      expect(find.text('Sent'), findsNothing);
      expect(find.textContaining('Waiting on the SDS Office'), findsNothing);
      // Who may send it back is the department here, not the SDS Office.
      expect(find.textContaining('the SDS Office returns it'), findsNothing);
      expect(
        find.textContaining('Moderator or Dean returns it'),
        findsOneWidget,
      );
    });

    testWidgets('says who returned it and what they said', (tester) async {
      final form = seeded(
        SapState.revisionRequested,
        by: SapReturnedBy.dean,
        remarks: 'Move it to the afternoon',
      );
      await tester.pumpWidget(host(SapProposalStatus(form: form)));
      await tester.pumpAndSettle();

      expect(find.text('Returned'), findsOneWidget);
      expect(find.textContaining('by the Dean'), findsOneWidget);
      expect(find.textContaining('Move it to the afternoon'), findsOneWidget);
      expect(toneOf(tester), BrutTone.coral);
      // It is open to the proposer again, so it is not "read-only".
      expect(find.textContaining('read-only'), findsNothing);
    });

    testWidgets('does not guess who returned it when it is not said', (
      tester,
    ) async {
      final form = seeded(
        SapState.revisionRequested,
        remarks: 'Fix the budget',
      );
      await tester.pumpWidget(host(SapProposalStatus(form: form)));
      await tester.pumpAndSettle();

      expect(find.text('Returned'), findsOneWidget);
      expect(find.textContaining('Fix the budget'), findsOneWidget);
      expect(find.textContaining('by the'), findsNothing);
    });

    testWidgets('reads a rejection as final, with the office\'s reason', (
      tester,
    ) async {
      final form = seeded(SapState.rejected)
        ..overallRemarks = 'Not an organizational activity'
        ..sectionRemarks = {
          SapRemarkSection.budget: 'Meals over the allowance',
        };
      await tester.pumpWidget(host(SapProposalStatus(form: form)));
      await tester.pumpAndSettle();

      expect(find.text('Rejected'), findsOneWidget);
      expect(find.textContaining('final'), findsOneWidget);
      expect(
        find.textContaining('Not an organizational activity'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Budget: Meals over the allowance'),
        findsOneWidget,
      );
      expect(toneOf(tester), BrutTone.coral);
      // Nothing opens again after a rejection.
      expect(find.textContaining('open again'), findsNothing);
    });

    testWidgets('still says the SDS Office has one it has', (tester) async {
      final form = seeded(SapState.pendingReview);
      await tester.pumpWidget(host(SapProposalStatus(form: form)));
      await tester.pumpAndSettle();

      expect(find.text('With the SDS Office'), findsOneWidget);
      expect(find.textContaining('the SDS Office returns it'), findsOneWidget);
    });
  });

  // Parts 1 to 3 are read-only after a rejection too, but "until it is
  // returned for revision" is false of it: nothing is returned after one.
  group('Part 1, when it is read-only', () {
    Future<void> openAt(WidgetTester tester, SapState state) async {
      // A fresh tree each time: a screen of the same type keeps the form it
      // first opened on.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        host(
          SapPart1Screen(
            form: SapForm(eventId: 'e1')..seedLocally(state: state),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('reads a rejection as final, not as waiting for a return', (
      tester,
    ) async {
      await openAt(tester, SapState.rejected);

      expect(find.textContaining('final'), findsOneWidget);
      final notice = banner(tester, 'final');
      expect(notice.text, contains('Rejected by the SDS Office'));
      expect(notice.tone, BrutTone.coral);
      expect(notice.icon, Icons.block);
      expect(find.textContaining('under review'), findsNothing);
      expect(find.textContaining('returned for revision'), findsNothing);
    });

    testWidgets('still says a proposal with the department is under review', (
      tester,
    ) async {
      await openAt(tester, SapState.pendingDepartmentReview);

      final notice = banner(tester, 'under review');
      expect(notice.text, contains('returned for revision'));
      expect(notice.tone, BrutTone.sun);
      expect(find.textContaining('final'), findsNothing);
    });
  });

  test(
    'the SDS Office\'s remarks list in the form\'s order, blanks left out',
    () {
      final form = SapForm(eventId: 'e1')
        ..overallRemarks = '  Not an organizational activity '
        ..sectionRemarks = {
          SapRemarkSection.other: 'Attach the venue letter',
          SapRemarkSection.budget: 'Meals over the allowance',
          SapRemarkSection.clearance: '   ',
        };

      // The form's order, not the order the server sent them in.
      expect(form.sdsRemarkLines(), [
        'Budget: Meals over the allowance',
        'Other: Attach the venue letter',
      ]);
      expect(form.sdsRemarkLines(overall: true), [
        'Not an organizational activity',
        'Budget: Meals over the allowance',
        'Other: Attach the venue letter',
      ]);
      expect(SapForm(eventId: 'e1').sdsRemarkLines(overall: true), isEmpty);
    },
  );
}
