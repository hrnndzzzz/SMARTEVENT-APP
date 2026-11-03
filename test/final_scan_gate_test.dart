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
import 'package:smartevent/screens/sap/sap_part5_screen.dart';
import 'package:smartevent/screens/sap/sap_part6_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// The final scan, and whose it is to record and upload.
///
/// The server takes the scan only while the proposal is `sds_signed`, and
/// slots 5 to 9 can be recorded only from there too. The button waited for
/// `pending_sap_review` instead, where the nine can never be recorded, so it
/// never opened. And the server takes the paper checkpoints, the scan and the
/// evaluation from the SDS Office alone, while the screens asked only whether
/// the session could write, which is an offline flag and not a role.
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

  /// The nine slots as the server lists them: the first [recorded] done, and
  /// the one after them open for recording.
  List<Map<String, dynamic>> slots(int recorded) => [
    for (var n = 1; n <= 9; n++)
      {
        'id': 's$n',
        'slot': n,
        'position': 'Position $n',
        'display_label': 'Reviewed by',
        'revision_no': 1,
        'status': n <= recorded ? 'recorded' : 'pending',
        'actionable': n == recorded + 1,
        'evidence': n <= recorded
            ? {
                'signer_name': 'Signer $n',
                'signer_reference': 'institution-person-00$n',
                'physical_signature_date': '2026-10-17',
                'recorded_on_behalf': true,
              }
            : null,
      },
  ];

  /// A proposal the server holds in [state], loaded, with [recorded] of its
  /// nine slots recorded. [readOnly] is the session losing the right to write
  /// after that, as when it goes offline.
  Future<SapForm> loaded(
    String state, {
    int recorded = 9,
    bool readOnly = false,
  }) async {
    final client = ApiClient(
      httpClient: MockClient(
        (request) async => json(
          request.url.path.endsWith('/workflow')
              ? {
                  'state': state,
                  'revision_no': 1,
                  'version': 4,
                  'completed_count': recorded,
                  'total_count': 9,
                  'steps': slots(recorded),
                }
              : {
                  'id': 'p1',
                  'event_id': 'e1',
                  'state': state,
                  'version': 4,
                  'revision_no': 1,
                  'details': {'title': 'Hack the Future'},
                  'collections': <String, dynamic>{},
                },
        ),
      ),
    );
    final form = SapForm(eventId: 'e1', service: SapService(client));
    await form.load();
    await form.loadWorkflow();
    // A form that never loaded holds nothing, and reads as locked to everyone.
    expect(form.state, SapState.fromWire(state));
    expect(form.workflow?.completedCount, recorded);
    client.readOnly = readOnly;
    return form;
  }

  /// Whether [label] is on screen as a button that can be pressed.
  bool pressable(WidgetTester tester, String label) => tester
      .widgetList<BrutButton>(find.widgetWithText(BrutButton, label))
      .any((button) => button.onPressed != null);

  /// The one banner whose text has [containing] in it.
  BrutInlineMessage banner(WidgetTester tester, String containing) =>
      tester.widget<BrutInlineMessage>(
        find.byWidgetPredicate(
          (w) => w is BrutInlineMessage && w.text.contains(containing),
        ),
      );

  /// The line under "Signed scan", whatever it says.
  BrutInlineMessage scanNotice(WidgetTester tester) =>
      tester.widget<BrutInlineMessage>(
        find.byWidgetPredicate(
          (w) => w is BrutInlineMessage && w.icon == Icons.upload_file,
        ),
      );

  /// Every account that is not the SDS Office, and none at all: nobody is
  /// taken for the office on a hunch.
  final everyoneElse = <UserRole?>[
    for (final role in UserRole.values)
      if (role != UserRole.sdsStaff) role,
    null,
  ];

  group('the final scan', () {
    testWidgets('opens once the SDS Office has signed, and not before', (
      tester,
    ) async {
      for (final state in SapState.values) {
        final form = await loaded(state.wireName);
        await open(tester, SapPart5Screen(form: form), role: UserRole.sdsStaff);

        expect(
          pressable(tester, 'Upload the signed scan'),
          state == SapState.sdsSigned,
          reason: state.wireName,
        );
      }
    });

    testWidgets('waits for the ninth checkpoint', (tester) async {
      final form = await loaded('sds_signed', recorded: 8);
      await open(tester, SapPart5Screen(form: form), role: UserRole.sdsStaff);

      expect(pressable(tester, 'Upload the signed scan'), isFalse);
      expect(scanNotice(tester).text, contains('All nine checkpoints'));
      expect(scanNotice(tester).tone, BrutTone.sun);
    });

    testWidgets('stays shut on a session that cannot write', (tester) async {
      final form = await loaded('sds_signed', readOnly: true);
      await open(tester, SapPart5Screen(form: form), role: UserRole.sdsStaff);

      expect(form.isReadOnly, isTrue);
      expect(pressable(tester, 'Upload the signed scan'), isFalse);
    });

    testWidgets('asks for what the server checks, not for six pages', (
      tester,
    ) async {
      final form = await loaded('sds_signed');
      await open(tester, SapPart5Screen(form: form), role: UserRole.sdsStaff);

      final notice = scanNotice(tester);
      expect(notice.tone, BrutTone.neutral);
      expect(notice.text, contains('flattened PDF'));
      expect(notice.text, contains('at least three pages'));
      expect(notice.text, contains('same page count'));
      expect(notice.text, contains('SDS-signed copy'));
      expect(notice.text, contains('10 MB'));
      expect(notice.text, isNot(contains('six')));
    });

    testWidgets('is not offered to anyone but the SDS Office', (tester) async {
      for (final role in everyoneElse) {
        // All nine recorded, and signed: the server would take the file.
        final form = await loaded('sds_signed');
        await open(tester, SapPart5Screen(form: form), role: role);

        expect(
          pressable(tester, 'Upload the signed scan'),
          isFalse,
          reason: '${role?.name}',
        );
      }
    });

    testWidgets('is said to be the SDS Office\'s to upload', (tester) async {
      for (final role in everyoneElse) {
        for (final recorded in [4, 9]) {
          final form = await loaded('sds_signed', recorded: recorded);
          await open(tester, SapPart5Screen(form: form), role: role);

          final reason = '${role?.name} with $recorded recorded';
          final notice = scanNotice(tester);
          expect(
            notice.text,
            'The SDS Office uploads the signed scan once all nine are '
            'recorded.',
            reason: reason,
          );
          expect(notice.tone, BrutTone.neutral, reason: reason);
          expect(find.textContaining('Upload the scanned'), findsNothing);
        }
      }
    });
  });

  group('the nine slots', () {
    testWidgets('open for recording to the SDS Office', (tester) async {
      for (final (state, recorded) in [
        ('pending_sap_review', 1),
        ('sds_signed', 4),
      ]) {
        final form = await loaded(state, recorded: recorded);
        await open(tester, SapPart5Screen(form: form), role: UserRole.sdsStaff);

        expect(
          find.widgetWithText(BrutButton, 'Record'),
          findsOneWidget,
          reason: state,
        );
      }
    });

    testWidgets('are not open to anyone else', (tester) async {
      for (final role in everyoneElse) {
        // Slot 5 is open, and recording it is the office's to do.
        final form = await loaded('sds_signed', recorded: 4);
        await open(tester, SapPart5Screen(form: form), role: role);

        expect(
          find.widgetWithText(BrutButton, 'Record'),
          findsNothing,
          reason: '${role?.name}',
        );
      }
    });

    testWidgets('are not open on a session that cannot write', (tester) async {
      final form = await loaded('sds_signed', recorded: 4, readOnly: true);
      await open(tester, SapPart5Screen(form: form), role: UserRole.sdsStaff);

      expect(find.widgetWithText(BrutButton, 'Record'), findsNothing);
    });

    testWidgets('say which of them open when', (tester) async {
      final form = await loaded('pending_sap_review', recorded: 1);
      await open(tester, SapPart5Screen(form: form), role: UserRole.sdsStaff);

      final hint = banner(tester, 'Slots 2 and 3');
      expect(hint.text, contains('Slots 2 and 3 can be recorded in either'));
      expect(hint.text, contains('Slots 5 to 9 open once the SDS Office has'));
      expect(hint.tone, BrutTone.neutral);
    });

    testWidgets('leave the printout open to everyone', (tester) async {
      for (final role in [...everyoneElse, UserRole.sdsStaff]) {
        final form = await loaded('sds_signed', recorded: 4);
        await open(tester, SapPart5Screen(form: form), role: role);

        expect(
          pressable(tester, 'Print for the signatories'),
          isTrue,
          reason: '${role?.name}',
        );
      }
    });
  });

  // Once the SDS Office has decided there is no road to a scan left to
  // describe: a rejection is final and no scan follows it, and an approval is
  // the scan itself. Part 5 went on telling everyone how to get to one.
  group('Part 5 after the SDS Office has decided', () {
    final readers = [UserRole.sdsStaff, UserRole.treasurer];

    testWidgets('says no signed scan follows a rejection', (tester) async {
      for (final role in readers) {
        // Rejected while the office was recording, so four slots are on file.
        final form = await loaded('rejected', recorded: 4);
        await open(tester, SapPart5Screen(form: form), role: role);

        final reason = role.name;
        final notice = scanNotice(tester);
        expect(
          notice.text,
          contains('Rejected by the SDS Office'),
          reason: reason,
        );
        expect(notice.text, contains('no signed scan'), reason: reason);
        expect(notice.tone, BrutTone.coral, reason: reason);
        for (final said in [
          'once all nine',
          'have to be recorded',
          'Slots 5 to 9',
        ]) {
          expect(
            find.textContaining(said),
            findsNothing,
            reason: '$reason: $said',
          );
        }
      }
    });

    testWidgets('closes the page of a rejection that has no slots', (
      tester,
    ) async {
      // The demo has no server, so what it seeds as rejected has no workflow.
      for (final role in readers) {
        final form = SapForm(eventId: 'e1')
          ..seedLocally(state: SapState.rejected);
        await open(tester, SapPart5Screen(form: form), role: role);

        final reason = role.name;
        expect(
          find.textContaining('open once the proposal is submitted'),
          findsNothing,
          reason: reason,
        );
        final line = banner(tester, 'Rejected by the SDS Office');
        expect(
          line.text,
          contains('Nothing more is recorded or uploaded'),
          reason: reason,
        );
        expect(line.tone, BrutTone.coral, reason: reason);
        expect(line.icon, Icons.block, reason: reason);
      }
    });

    testWidgets('says the signed scan is stored once approved', (tester) async {
      for (final state in ['approved', 'completed']) {
        for (final role in readers) {
          final form = await loaded(state);
          await open(tester, SapPart5Screen(form: form), role: role);

          final reason = '${role.name} at $state';
          final notice = scanNotice(tester);
          expect(notice.text, contains('is stored'), reason: reason);
          expect(notice.text, contains('cannot be replaced'), reason: reason);
          expect(notice.tone, BrutTone.mint, reason: reason);
          expect(
            find.textContaining('Upload the scanned'),
            findsNothing,
            reason: reason,
          );
          expect(
            find.textContaining('uploads the signed scan'),
            findsNothing,
            reason: reason,
          );
        }
      }
    });
  });

  group('Part 6', () {
    SapSingleChoice<SapEvaluationOutcome> outcome(WidgetTester tester) =>
        tester.widget(find.byType(SapSingleChoice<SapEvaluationOutcome>));

    BrutTextField remarks(WidgetTester tester) =>
        tester.widget(find.byType(BrutTextField));

    testWidgets('is the SDS Office\'s to record', (tester) async {
      final form = await loaded('approved');
      await open(tester, SapPart6Screen(form: form), role: UserRole.sdsStaff);

      expect(outcome(tester).enabled, isTrue);
      expect(remarks(tester).enabled, isTrue);
      expect(pressable(tester, 'Record evaluation'), isFalse);

      await tester.tap(find.text('Conducted'));
      await tester.enterText(find.byType(TextField), 'It ran well.');
      await tester.pump();

      expect(pressable(tester, 'Record evaluation'), isTrue);
    });

    testWidgets('is shut to everyone else', (tester) async {
      for (final role in everyoneElse) {
        final form = await loaded('approved');
        await open(tester, SapPart6Screen(form: form), role: role);

        final reason = '${role?.name}';
        expect(outcome(tester).enabled, isFalse, reason: reason);
        expect(remarks(tester).enabled, isFalse, reason: reason);
        expect(pressable(tester, 'Record evaluation'), isFalse, reason: reason);
      }
    });

    testWidgets('keeps its button shut without leaning on the fields', (
      tester,
    ) async {
      for (final role in everyoneElse) {
        final form = await loaded('approved');
        await open(tester, SapPart6Screen(form: form), role: role);

        // The screen gives them no way to type this. A complete answer put in
        // by other means must still not open the button.
        remarks(tester).controller!.text = 'It ran well.';
        outcome(tester).onChanged(SapEvaluationOutcome.conducted);
        await tester.pump();

        expect(
          pressable(tester, 'Record evaluation'),
          isFalse,
          reason: '${role?.name}',
        );
      }
    });

    testWidgets('is shut to the office on a session that cannot write', (
      tester,
    ) async {
      final form = await loaded('approved', readOnly: true);
      await open(tester, SapPart6Screen(form: form), role: UserRole.sdsStaff);

      expect(form.isReadOnly, isTrue);
      expect(outcome(tester).enabled, isFalse);
      expect(remarks(tester).enabled, isFalse);
      expect(pressable(tester, 'Record evaluation'), isFalse);
    });
  });
}
