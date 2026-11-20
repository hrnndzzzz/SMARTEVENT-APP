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
      // The backend raises exactly one kind today. Anything added
      // later that follows area_outcome should need no change here.
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
