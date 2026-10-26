import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/screens/settings_screen.dart';
import 'package:smartevent/screens/signin_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/sfx.dart';
import 'package:smartevent/state/user_role.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Built and unreachable is not built.
///
/// Four screens in this project have now been written, tested and left
/// with no way into them from the app. Every time, the tests passed. So
/// the way in gets a test of its own — both the demo's way in below, and
/// a sweep that fails when any screen has none at all.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget signIn(AppState app) => ChangeNotifierProvider.value(
    value: app,
    child: MaterialApp(theme: AppTheme.light(), home: const SignInScreen()),
  );

  testWidgets('holding the heading offers the demo, and asks first', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    final app = AppState();

    await tester.pumpWidget(signIn(app));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Welcome back'));
    await tester.pumpAndSettle();

    expect(find.text('Access demo mode?'), findsOneWidget);
    expect(app.isDemoMode, isFalse, reason: 'not until it is accepted');
  });

  testWidgets('cancelling leaves everything alone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    final app = AppState();

    await tester.pumpWidget(signIn(app));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Welcome back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(app.isDemoMode, isFalse);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('accepting starts the demo somewhere that can actually do things', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    final app = AppState();

    await tester.pumpWidget(signIn(app));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Welcome back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter demo'));
    await tester.pumpAndSettle();

    expect(app.isDemoMode, isTrue);
    // Not the officer: officers are view-only, so starting there opens
    // the demo unable to create anything.
    expect(app.currentRole, UserRole.treasurer);
    expect(app.currentRole!.canProposeEvents, isTrue);
  });

  testWidgets('and the hold still works a second time', (tester) async {
    // The old shortcut opened once per launch, which made every role but
    // the first unreachable without killing the app.
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    final app = AppState();

    await tester.pumpWidget(signIn(app));
    await tester.pumpAndSettle();

    for (var attempt = 1; attempt <= 3; attempt++) {
      await tester.longPress(find.text('Welcome back'));
      await tester.pumpAndSettle();

      expect(
        find.text('Access demo mode?'),
        findsOneWidget,
        reason: 'hold number $attempt did nothing',
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  group('the role picker', () {
    Widget settings(AppState app) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => SfxPlayer()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SettingsScreen(),
      ),
    );

    testWidgets('offers every role the demo can be seen as', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      final app = AppState()..enterDemo(role: UserRole.officer);

      await tester.pumpWidget(settings(app));
      await tester.pumpAndSettle();

      for (final role in [
        UserRole.officer,
        UserRole.treasurer,
        UserRole.adviser,
        UserRole.sdsStaff,
        UserRole.admin,
        UserRole.superAdmin,
      ]) {
        expect(find.text(role.label), findsWidgets, reason: role.name);
      }
    });

    testWidgets('switching changes who is looking', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      final app = AppState()..enterDemo(role: UserRole.officer);

      await tester.pumpWidget(settings(app));
      await tester.pumpAndSettle();

      await tester.tap(find.text(UserRole.sdsStaff.label).first);
      await tester.pumpAndSettle();

      expect(app.currentRole, UserRole.sdsStaff);
      expect(app.currentAccount?.role, UserRole.sdsStaff);
    });

    testWidgets('and the review demo is still reachable', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      final app = AppState()..enterDemo(role: UserRole.officer);

      await tester.pumpWidget(settings(app));
      await tester.pumpAndSettle();

      expect(find.text('Review a proposal'), findsOneWidget);
    });

    testWidgets('and none of it shows outside the demo', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));

      await tester.pumpWidget(settings(AppState()));
      await tester.pumpAndSettle();

      expect(find.text('Review a proposal'), findsNothing);
      expect(find.text(UserRole.sdsStaff.label), findsNothing);
    });
  });

  // Named ways in are only as good as someone remembering to write one.
  // This is the net underneath: nothing under lib/screens/ ships unless
  // some other file in the app names it.
  group('every screen has a way in', () {
    // Dedicated comment lines, dropped. A screen named only in prose
    // ("pushes FooScreen") is not reachable, and counting that as a
    // reference is how an orphan slips through this test.
    String code(String source) => [
      for (final line in source.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

    test('no screen is left with no way into it', () {
      final lib = Directory('lib');
      expect(
        lib.existsSync(),
        isTrue,
        reason: 'run flutter test from the project root',
      );

      final sources = {
        for (final file in lib.listSync(recursive: true))
          if (file is File && file.path.endsWith('.dart'))
            file.path: code(file.readAsStringSync()),
      };

      final sep = Platform.pathSeparator;
      final screens = RegExp(r'^class\s+([A-Z]\w*Screen)\b', multiLine: true);

      final orphans = <String>[];
      for (final source in sources.entries) {
        if (!source.key.contains('${sep}screens$sep')) continue;
        for (final match in screens.allMatches(source.value)) {
          final name = match.group(1)!;
          final named = RegExp('\\b$name\\b');
          final reachable = sources.entries.any(
            (other) => other.key != source.key && named.hasMatch(other.value),
          );
          if (!reachable) orphans.add('$name (${source.key})');
        }
      }

      expect(
        orphans,
        isEmpty,
        reason:
            'nothing in the app opens these, so nobody can reach them:\n'
            '${orphans.join('\n')}\n'
            'Give each one a way in, or delete it.',
      );
    });

    test('and the sweep actually finds the screens it sweeps', () {
      // A pattern that matches nothing would pass the test above forever,
      // however many orphans shipped.
      final screens = RegExp(r'^class\s+([A-Z]\w*Screen)\b', multiLine: true);
      final names = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (!file.path.contains(
          '${Platform.pathSeparator}screens${Platform.pathSeparator}',
        )) {
          continue;
        }
        for (final match in screens.allMatches(code(file.readAsStringSync()))) {
          names.add(match.group(1)!);
        }
      }

      expect(names, contains('SettingsScreen'));
      expect(names.length, greaterThan(20), reason: '${names.length} found');
    });
  });
}
