import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/screens/signin_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Built and unreachable is not built.
///
/// Two screens in this project have now been written, tested and left
/// with no way into them from the app. Both times the tests passed. So
/// the way in gets a test of its own.
void main() {
  testWidgets('holding the sign-in heading reaches the review demo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 1000));

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SignInScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Welcome back'));
    await tester.pumpAndSettle();

    expect(
      find.text('Review a proposal'),
      findsOneWidget,
      reason: 'the hold must offer the demo in every build, not just debug',
    );
    expect(find.text('Explore as a treasurer'), findsOneWidget);
  });

  testWidgets('choosing a role leaves the sign-in screen behind', (
    tester,
  ) async {
    // The gate that decides welcome-or-app is the route underneath this
    // one, so setting the state is not enough: the app comes up buried
    // under the sign-in screen unless the stack is unwound.
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 1000));

    final app = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SignInScreen(),
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Welcome back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explore as a treasurer'));
    await tester.pumpAndSettle();

    expect(app.isDemoMode, isTrue);
    expect(
      find.text('Welcome back'),
      findsNothing,
      reason: 'the sign-in screen must not still be on top of the app',
    );
  });
}
