import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/main.dart';
import 'package:smartevent/screens/home_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';

/// The first sign-in walks through the whole app once — the dashboard,
/// the Menu, each module, the Events page, its list and a new proposal's
/// cover — and Settings can ask for it again.
void main() {
  // Not pumpAndSettle: the bell rings on a repeating controller.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<AppState> signIn(WidgetTester tester, UserRole role) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SmartEventApp());
    await tester.pump(const Duration(milliseconds: 500));
    final app = tester.element(find.byType(Scaffold).first).read<AppState>();
    app.enterDemo(role: role);
    await frames(tester);
    return app;
  }

  /// The card's eyebrow, such as "MONEY · 2 OF 3", or null with no tour up.
  String? eyebrow() {
    final label = find.textContaining(RegExp(r'\d+ OF \d+$'));
    if (label.evaluate().isEmpty) return null;
    return (label.evaluate().first.widget as Text).data;
  }

  /// Presses Next until the tour ends or reaches [stopAt], and returns
  /// the sections it passed through, in order.
  Future<List<String>> walk(WidgetTester tester, {String? stopAt}) async {
    final sections = <String>[];
    for (var i = 0; i < 60; i++) {
      final label = eyebrow();
      if (label == null) break;
      final section = label.split(' · ').first;
      if (sections.isEmpty || sections.last != section) sections.add(section);
      if (section == stopAt) break;
      final next = find.text('Next');
      await tester.tap(next.evaluate().isEmpty ? find.text('Done') : next);
      await frames(tester);
    }
    return sections;
  }

  void expectHome(WidgetTester tester) {
    expect(eyebrow(), isNull);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(HomeScreen))).canPop(),
      isFalse,
    );
  }

  testWidgets('one tour walks every module and ends on the dashboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await signIn(tester, UserRole.officer);
    expect(eyebrow(), 'DASHBOARD · 1 OF 5');

    expect(await walk(tester), [
      'DASHBOARD',
      'MENU',
      'MONEY',
      'INVENTORY',
      'ANALYTICS',
      'FLAGGED',
      'EVENTS',
      'ALL EVENTS',
      'CREATE EVENT',
    ]);
    expectHome(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Skip inside a module ends it all and comes home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await signIn(tester, UserRole.officer);
    await walk(tester, stopAt: 'MONEY');
    expect(eyebrow(), startsWith('MONEY · 1 OF'));

    await tester.tap(find.text('Skip'));
    await frames(tester);
    expectHome(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a first sign-in gets the tour, a second does not', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final app = await signIn(tester, UserRole.officer);
    expect(eyebrow(), isNotNull);
    await tester.tap(find.text('Skip'));
    await frames(tester);

    await app.signOut();
    await frames(tester);
    await signIn(tester, UserRole.officer);
    expect(eyebrow(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // The Adviser reviews money rather than recording it.
  testWidgets('Settings replays it, without stops a role has no use for', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'tour.seenBy': <String>['demo'],
    });
    await signIn(tester, UserRole.adviser);
    expect(eyebrow(), isNull);

    tester
        .element(find.byType(Scaffold).first)
        .read<AppSettings>()
        .tourRequests
        .value++;
    await frames(tester);
    expect(eyebrow(), 'DASHBOARD · 1 OF 4');

    await walk(tester, stopAt: 'MONEY');
    expect(eyebrow(), 'MONEY · 1 OF 2');
    await tester.pumpWidget(const SizedBox());
  });
}
