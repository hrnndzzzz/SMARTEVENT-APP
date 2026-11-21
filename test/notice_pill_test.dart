import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smartevent/screens/home_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/state/sfx.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/widgets/brand_pill.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/widgets/notice_kind.dart';

/// The bell says what arrived, then goes back to being a bell.
///
/// Asked for as "if theres a notifacation, the notif bar should be
/// extended and the notification text will show but only what type of
/// notification it is, is it approval, inventory added, etc, should be
/// color coded too, the animation should be similar to what we did on
/// smartevent bar when its online status changes".
void main() {
  group('the kind decides the word and the colour', () {
    test('the area gives the word', () {
      expect(noticeArea('sap_submitted'), 'Approval');
      expect(noticeArea('expense_approved'), 'Expense');
      expect(noticeArea('inventory_low'), 'Inventory');
      expect(noticeArea('registration_confirmation'), 'Account');
    });

    test('the outcome gives the colour', () {
      expect(noticeOutcome('sap_approved'), BrutTone.mint);
      expect(noticeOutcome('sap_rejected'), BrutTone.coral);
      expect(noticeOutcome('sap_submitted'), BrutTone.sun);
    });

    test('a kind nobody has seen still comes out sensibly', () {
      // Anything the backend adds later that follows area_outcome
      // should need no change here.
      expect(noticeBadge('income_confirmed'), (
        label: 'Income',
        tone: BrutTone.mint,
      ));
      // And one that follows no pattern is news, not a verdict.
      expect(noticeBadge('something'), (
        label: 'Update',
        tone: BrutTone.neutral,
      ));
    });

    test('a kind with no outcome is not given one', () {
      expect(noticeOutcome('sap'), BrutTone.neutral);
      expect(noticeOutcome('sap_reminder'), BrutTone.neutral);
    });
  });

  // Every SAP notice the server sends arrives as the one kind
  // `sap_workflow`, which says nothing about how the thing went: read
  // on its own it gives the right word in no colour at all. The step is
  // in the payload as `action`, so these are the strings that have to
  // produce the colour.
  //
  // The list is every action in `notify` in the backend's
  // `app/services/sap.py`. If the backend adds one and it is missing
  // here, the pill goes grey rather than wrong — but a grey approval is
  // the bug this group exists to catch.
  group('a SAP notice is coloured by its action, not its kind', () {
    test('the kind alone gives the word and no verdict', () {
      expect(noticeBadge('sap_workflow'), (
        label: 'Approval',
        tone: BrutTone.neutral,
      ));
    });

    test('something went through', () {
      for (final action in [
        'sap_revision_signed',
        'sap_approved_with_physical_evidence',
        'sap_evaluated',
        'sap_dean_approved',
      ]) {
        expect(noticeBadge('sap_workflow', action: action), (
          label: 'Approval',
          tone: BrutTone.mint,
        ), reason: '$action should read as good news');
      }
    });

    test('something did not', () {
      for (final action in [
        'sap_returned',
        'sap_department_returned',
        'sap_signed_revision_correction_requested',
        'sap_rejected',
        'sap_auto_rejected',
        'sap_withdrawn',
      ]) {
        expect(noticeBadge('sap_workflow', action: action), (
          label: 'Approval',
          tone: BrutTone.coral,
        ), reason: '$action should read as bad news');
      }
    });

    test('something is now waiting on a person', () {
      expect(noticeBadge('sap_workflow', action: 'sap_submitted'), (
        label: 'Approval',
        tone: BrutTone.sun,
      ));
    });

    test('a step with no verdict in it stays news', () {
      // A checkpoint being recorded is neither good nor bad, and the
      // backend's own fallback action is not a verdict either.
      for (final action in ['sap_checkpoint_recorded', 'sap_updated']) {
        expect(
          noticeBadge('sap_workflow', action: action).tone,
          BrutTone.neutral,
          reason: '$action was given a verdict it does not have',
        );
      }
    });

    test('an action never overrules a kind that has its own outcome', () {
      // Belt and braces: were the backend ever to name kinds properly
      // again, a stale action in the payload must not recolour them.
      expect(
        noticeBadge('expense_approved', action: 'sap_rejected').tone,
        BrutTone.mint,
      );
      expect(
        noticeBadge('sap_rejected', action: 'sap_approved').tone,
        BrutTone.coral,
      );
    });
  });

  group('the pill in the header', () {
    Widget host(AppState app) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
        ChangeNotifierProvider(create: (_) => NoticeShelf()),
        ChangeNotifierProvider(create: (_) => SfxPlayer()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(accent: app.themeColor),
        home: const HomeScreen(),
      ),
    );

    testWidgets('it names the newest unread notice, then stops', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 2600);
      addTearDown(tester.view.reset);

      final app = AppState()..enterDemo(role: UserRole.treasurer);
      addTearDown(app.dispose);
      await tester.pumpWidget(host(app));
      await tester.pump(const Duration(milliseconds: 400));

      final newest = app.notices.where((n) => n.isUnread).first;
      final word = noticeArea(newest.kind);

      expect(
        find.text(word),
        findsOneWidget,
        reason: 'the header never said what arrived',
      );

      // It is an interruption, not a label: it goes away on its own.
      await tester.pump(const Duration(seconds: 4));
      expect(
        find.text(word),
        findsNothing,
        reason: 'the pill stayed extended and the header never came back',
      );
    });

    testWidgets('the colour comes from the step, not the kind', (tester) async {
      // The demo's newest notice is a submission, worded the way the
      // server words it: kind `sap_workflow`, step in the payload. Read
      // from the kind alone the pill would be grey, so a coloured pill
      // is proof the header passed the action through.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 2600);
      addTearDown(tester.view.reset);

      final app = AppState()..enterDemo(role: UserRole.treasurer);
      addTearDown(app.dispose);

      final newest = app.notices.where((n) => n.isUnread).first;
      expect(
        newest.kind,
        'sap_workflow',
        reason: 'the demo stopped matching how the server names notices',
      );
      expect(noticeBadge(newest.kind).tone, BrutTone.neutral);
      expect(
        noticeBadge(newest.kind, action: newest.action).tone,
        isNot(BrutTone.neutral),
      );

      await tester.pumpWidget(host(app));
      await tester.pump(const Duration(milliseconds: 400));
      // Twice over: the colour crosses a fade and then the surface's
      // own press animation, and one frame leaves it mid-flight. Still
      // well inside the three seconds before the pill retracts.
      await tester.pump(BrandPill.motion);
      await tester.pump(BrandPill.motion);

      final context = tester.element(find.byType(HomeScreen));
      final wanted = noticeBadge(
        newest.kind,
        action: newest.action,
      ).tone.fill(context);

      // By its own semantics label rather than the word, which the
      // dashboard says elsewhere too.
      final pill = find.descendant(
        of: find.bySemanticsLabel(RegExp('newest: Approval')),
        matching: find.byType(DecoratedBox),
      );
      expect(
        tester
            .widgetList<DecoratedBox>(pill)
            .map((box) => (box.decoration as BoxDecoration).color),
        contains(wanted),
        reason: 'the pill was not wearing the colour of its step',
      );
    });

    testWidgets('reduced motion gets a plain bell', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 2600);
      addTearDown(tester.view.reset);

      final app = AppState()..enterDemo(role: UserRole.treasurer);
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: host(app),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      final newest = app.notices.where((n) => n.isUnread).first;
      expect(find.text(noticeArea(newest.kind)), findsNothing);
    });

    testWidgets('it still opens the inbox', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 2600);
      addTearDown(tester.view.reset);

      final app = AppState()..enterDemo(role: UserRole.treasurer);
      addTearDown(app.dispose);
      await tester.pumpWidget(host(app));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.bySemanticsLabel(RegExp('Notifications')).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(HomeScreen), findsOneWidget);
      // Something opened over the dashboard rather than nothing
      // happening: the pill replaced a button and must still be one.
      expect(find.text('Notifications'), findsWidgets);
    });
  });
}
