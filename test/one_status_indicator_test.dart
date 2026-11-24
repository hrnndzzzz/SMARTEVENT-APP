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
import 'package:smartevent/widgets/connection_banner.dart';
import 'package:smartevent/widgets/notice_kind.dart';

/// One place says where the connection stands. Never two.
///
/// Reported as "the status floating pill should not appear alongside
/// with the smartevent pill cause it will look like we have two online
/// status indicators". There are two ways that can happen — the
/// floating pill drawing over a header that has already undertaken to
/// say it, and the notice pill going coloured beside a wordmark that
/// has also gone coloured — so both are covered here.
void main() {
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
      home: const ConnectionBanner(child: HomeScreen()),
    ),
  );

  Future<AppState> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 2600);
    addTearDown(tester.view.reset);
    final app = AppState()..enterDemo(role: UserRole.officer);
    addTearDown(app.dispose);
    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 400));
    return app;
  }

  ConnectionNews newsOf(WidgetTester tester) {
    final context = tester.element(find.byType(HomeScreen));
    final found = ConnectionNews.maybeOf(context);
    expect(found, isNotNull, reason: 'no connection scope in the tree');
    return found!;
  }

  testWidgets('the header having undertaken to say it, nothing floats', (
    tester,
  ) async {
    await open(tester);

    newsOf(tester).say('Offline', offline: true);
    await tester.pump(const Duration(milliseconds: 500));

    // The word appears once — in the wordmark, which claimed it.
    expect(
      find.text('Offline'),
      findsOneWidget,
      reason: 'the floating pill said it as well as the header',
    );
  });

  testWidgets('the notice pill goes quiet while the connection speaks', (
    tester,
  ) async {
    final app = await open(tester);
    final newest = app.notices.where((n) => n.isUnread).first;
    final word = noticeArea(newest.kind);

    // The pill names the arrival on open.
    expect(find.text(word), findsOneWidget);

    // Now the connection changes while it is still out. Two tinted
    // pills side by side read as two indicators disagreeing.
    newsOf(tester).say('Offline', offline: true);
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text(word),
      findsNothing,
      reason: 'the notice pill stayed coloured beside a coloured wordmark',
    );
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('the notice may speak again once the connection stops', (
    tester,
  ) async {
    final app = await open(tester);
    final newest = app.notices.where((n) => n.isUnread).first;

    final news = newsOf(tester);
    news.say('Offline', offline: true);
    await tester.pump(const Duration(milliseconds: 500));
    news.clear();
    await tester.pump(const Duration(milliseconds: 500));

    // Suppressed, not cancelled: the hold is still running, so the
    // word comes back rather than being lost to a passing blip.
    expect(find.text(noticeArea(newest.kind)), findsOneWidget);
  });
}
