import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/notice_shelf.dart';
import 'package:smartevent/theme/app_layout.dart';
import 'package:smartevent/widgets/app_header.dart';
import 'package:smartevent/widgets/popover.dart';

/// The badge and the panel it opens must agree.
///
/// notification_menu.dart states the rule in its own doc comment — "the
/// number on the badge is the length of this list" — and it was broken:
/// the badge counted every unread notice while the panel hid the ones
/// this phone had swiped away.
void main() {
  Widget host(AppState app, NoticeShelf shelf) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<NoticeShelf>.value(value: shelf),
    ],
    child: const MaterialApp(home: Scaffold(body: AppHeader())),
  );

  String? badgeText(WidgetTester tester) {
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final value = text.data;
      if (value != null && int.tryParse(value) != null) return value;
    }
    return null;
  }

  group('the badge counts what the panel will show', () {
    testWidgets('all three unread, nothing swiped', (tester) async {
      final app = AppState()..enterDemo();
      await tester.pumpWidget(host(app, NoticeShelf()));

      expect(app.unreadNoticeCount, 3);
      expect(badgeText(tester), '3');
    });

    testWidgets('swiping one away takes it off the badge', (tester) async {
      final app = AppState()..enterDemo();
      final shelf = NoticeShelf();
      await tester.pumpWidget(host(app, shelf));
      expect(badgeText(tester), '3');

      shelf.dismiss(app.notices.first.id);
      await tester.pump();

      expect(
        badgeText(tester),
        '2',
        reason: 'the panel now has two rows, so the badge must say two',
      );
      expect(
        app.unreadNoticeCount,
        3,
        reason: "the server's own count is untouched by a local swipe",
      );
    });

    testWidgets('reading one takes it off the badge', (tester) async {
      final app = AppState()..enterDemo();
      await tester.pumpWidget(host(app, NoticeShelf()));

      await app.markNoticeRead(app.notices.first);
      await tester.pump();

      expect(badgeText(tester), '2');
    });

    testWidgets('no badge at all once everything is dealt with', (
      tester,
    ) async {
      final app = AppState()..enterDemo();
      await tester.pumpWidget(host(app, NoticeShelf()));

      for (final notice in [...app.notices]) {
        await app.markNoticeRead(notice);
      }
      await tester.pump();

      expect(badgeText(tester), isNull, reason: 'a zero is not news');
    });
  });

  group('a popover hangs off the control that opened it', () {
    // A real phone: the SM-A515F this was checked on is 411pt wide.
    const screen = Size(411, 892);

    Future<Rect> frameRect(WidgetTester tester, Rect? anchor) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: screen),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: PopoverFrame(
              anchor: anchor,
              child: Container(key: const Key('panel'), height: 200),
            ),
          ),
        ),
      );
      return tester.getRect(find.byKey(const Key('panel')));
    }

    testWidgets('its right edge sits on the control’s right edge', (
      tester,
    ) async {
      // Where the bell actually sits: second from the right, with the
      // avatar outboard of it. This is the case that was wrong — the
      // panel lined up with the avatar instead of with the bell.
      const bell = Rect.fromLTWH(311, 20, 38, 38);

      final panel = await frameRect(tester, bell);

      expect(panel.right, closeTo(bell.right, 0.5));
      expect(panel.top, greaterThan(bell.bottom));
    });

    testWidgets('a control near the left edge still gets a panel on screen', (
      tester,
    ) async {
      const control = Rect.fromLTWH(8, 20, 38, 38);

      final panel = await frameRect(tester, control);

      expect(panel.left, greaterThanOrEqualTo(AppLayout.popoverMargin - 0.5));
      expect(panel.right, lessThanOrEqualTo(screen.width));
    });

    testWidgets('an unmeasurable control falls back to the corner', (
      tester,
    ) async {
      final panel = await frameRect(tester, null);

      expect(panel.top, closeTo(AppLayout.popoverTop, 0.5));
      expect(
        panel.right,
        closeTo(screen.width - AppLayout.popoverMargin, 0.5),
      );
    });
  });
}
