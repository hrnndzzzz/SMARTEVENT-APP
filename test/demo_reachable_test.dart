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
/// Three screens in this project have now been written, tested and left
/// with no way into them from the app. Every time, the tests passed. So
/// the way in gets a test of its own.
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
}
