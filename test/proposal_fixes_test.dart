import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/models/academic.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/screens/sap/proposal_steps.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

import 'support/complete_proposal.dart';

/// A proposal is not sent half-filled, leaving one keeps nothing the
/// proposer did not choose to keep, a fast tap does one thing, and a
/// never-sent draft can be deleted by whoever may.
void main() {
  Widget host(Widget home, {AppState? app}) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app ?? AppState()),
      ChangeNotifierProvider(create: (_) => AppSettings()),
      ChangeNotifierProvider(create: (_) => Reachability()),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: home),
  );

  group('a half-filled proposal is not sent', () {
    test('an empty form lists what is missing, a filled one nothing', () {
      final empty = SapForm();
      expect(
        empty.missingForSubmit,
        containsAll(['Activity title', 'Start time', 'Venue', 'Program flow']),
      );
      expect(filledIn(SapForm()).missingForSubmit, isEmpty);
    });

    test('a breakdown that does not add up to the budget is missing', () {
      final form = filledIn(SapForm())
        ..updateDetails((d) => d.copyWith(totalBudget: '3000.00'));
      expect(form.missingForSubmit, [
        'Budget breakdown that adds up to the budget',
      ]);
    });

    test('submitting it is refused here, naming what is missing', () async {
      final form = SapForm()..updateDetails((d) => d.copyWith(title: 'Hi'));
      expect(await form.submit(), isFalse);
      expect(form.error, startsWith('Fill in these first: Organization'));
      expect(form.error, isNot(contains('Activity title')));
    });

    testWidgets('the send button is grey, and says why', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 1600);
      addTearDown(tester.view.reset);

      Future<BrutButton> hub(SapForm form) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(host(SapFormScreen(form: form)));
        await tester.pump(const Duration(milliseconds: 400));
        return tester.widget<BrutButton>(
          find.widgetWithText(BrutButton, 'Submit for review'),
        );
      }

      expect((await hub(SapForm())).onPressed, isNull);
      expect(find.textContaining('To send it for review, fill in:'), findsOneWidget);

      expect((await hub(filledIn(SapForm()))).onPressed, isNotNull);
      expect(find.textContaining('To send it for review'), findsNothing);
    });
  });

  group('leaving keeps only what was chosen', () {
    late AppState app;
    late SapForm form;
    late String id;

    /// A demo account, and a form whose event [made] says who made.
    Future<void> setUp({required bool made}) async {
      app = AppState()..enterDemo();
      await app.addEvent(
        title: 'Started then left',
        estimatedCost: 0,
        schoolYear: '2026-2027',
        semester: Semester.first,
        eventScope: EventScope.organizational,
        submitNow: false,
        onCreated: (created) => id = created,
      );
      form = SapForm();
      await form.bindEvent(id, made: made);
    }

    Future<void> leaveBy(WidgetTester tester, String choice) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => LeaveProposal.confirm(
                  context,
                  save: () async => true,
                  form: form,
                ),
                child: const Text('go'),
              ),
            ),
          ),
          app: app,
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
    }

    bool onRecord() => app.events.any((e) => e.remoteId == id);

    testWidgets('"Go back" deletes the event this visit made', (tester) async {
      await setUp(made: true);
      expect(onRecord(), isTrue);

      await leaveBy(tester, 'Go back');

      expect(onRecord(), isFalse, reason: 'starting again made a second one');
      expect(form.hasEvent, isFalse);
    });

    testWidgets('"Save as draft" keeps it, even past a later "Go back"', (
      tester,
    ) async {
      await setUp(made: true);
      await leaveBy(tester, 'Save as draft');
      await leaveBy(tester, 'Go back');

      expect(onRecord(), isTrue);
    });

    testWidgets('a draft opened to carry on is never deleted', (tester) async {
      await setUp(made: false);
      await leaveBy(tester, 'Go back');

      expect(onRecord(), isTrue);
    });

    testWidgets('the phone back button asks too', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SapPart1Screen(form: SapForm()),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Leave this proposal?'), findsOneWidget);

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  });

  group('one tap, one action', () {
    testWidgets('a page opened by a tap is opened once', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Center(
              child: BrutButton(
                label: 'Open',
                onPressed: () {
                  opened++;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const Text('page')),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.tap(find.text('Open'), warnIfMissed: false);
      await tester.tap(find.text('Open'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(opened, 1);
    });

    testWidgets('work still running takes no second tap', (tester) async {
      var started = 0;
      var running = Completer<void>();
      await tester.pumpWidget(
        host(
          Center(
            child: BrutButton(
              label: 'Save',
              onPressed: () async {
                started++;
                await running.future;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(started, 1);

      running.complete();
      await tester.pump();
      running = Completer<void>()..complete();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(started, 2, reason: 'free again once the first has finished');
    });
  });

  group('deleting a draft', () {
    EventItem draft({String? by}) => EventItem(
      remoteId: 'demo-ev-delete-me',
      title: 'Alumni Homecoming Night',
      org: 'ACPES',
      date: '11/21/2026',
      budget: '0',
      status: EventApprovalStatus.draft,
      proposedBy: by,
    );

    testWidgets('only after the title is typed, by an administrator', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 1600);
      addTearDown(tester.view.reset);
      final app = AppState()..enterDemo(role: UserRole.admin);
      final event = draft(by: 'someone-else');
      app.events.insert(0, event);

      // Opened from a list, as in the app, so there is a page to go back to.
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EventDetailScreen(event: event),
                  ),
                ),
                child: const Text('the list'),
              ),
            ),
          ),
          app: app,
        ),
      );
      await tester.tap(find.text('the list'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete draft'));
      await tester.pumpAndSettle();

      BrutButton delete() =>
          tester.widget<BrutButton>(find.widgetWithText(BrutButton, 'Delete'));
      expect(delete().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Alumni Homecoming');
      await tester.pump();
      expect(delete().onPressed, isNull, reason: 'not the whole title');
      await tester.enterText(find.byType(TextField), 'Alumni Homecoming Night');
      await tester.pump();
      await tester.tap(find.widgetWithText(BrutButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(app.events.contains(event), isFalse);
      expect(find.text('Draft deleted.'), findsOneWidget);
      expect(find.text('the list'), findsOneWidget, reason: 'back to the list');
    });

    test('offered to its proposer and administrators, for drafts only', () {
      final proposer = AppState()..enterDemo();
      final mine = draft(by: proposer.currentAccount!.id);
      expect(proposer.canDeleteDraft(mine), isTrue);
      expect(proposer.canDeleteDraft(draft(by: 'someone-else')), isFalse);
      expect(
        proposer.canDeleteDraft(
          mine..status = EventApprovalStatus.pendingAdviser,
        ),
        isFalse,
      );
      expect(
        (AppState()..enterDemo(role: UserRole.admin)).canDeleteDraft(
          draft(by: 'someone-else'),
        ),
        isTrue,
      );
    });
  });
}
