import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/change_password_screen.dart';
import 'package:smartevent/screens/forgot_password_screen.dart';
import 'package:smartevent/screens/proposal_letters_screen.dart';
import 'package:smartevent/screens/register_screen.dart';
import 'package:smartevent/screens/verify_otp_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Smoke tests for the screens added with the six-role rework.
///
/// They render each screen and exercise the client-side validation that
/// runs before any network call, so a broken layout or a bad guard shows up
/// here rather than on a device. Nothing here touches the backend.
Widget _host(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => AppState(),
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

void main() {
  testWidgets('register screen renders without a role picker', (tester) async {
    await tester.pumpWidget(_host(const RegisterScreen()));

    expect(find.text('Create your account'), findsOneWidget);
    // Role, name and department come from the roster entry — offering any
    // of them here would be the self-assignment hole the backend closed.
    expect(find.text('Officer'), findsNothing);
    expect(find.text('Treasurer'), findsNothing);
    expect(find.text('Adviser'), findsNothing);
  });

  testWidgets('register screen rejects a short password before calling out',
      (tester) async {
    await tester.pumpWidget(_host(const RegisterScreen()));

    await tester.enterText(find.byType(TextField).at(0), 'someone@lcup.edu.ph');
    await tester.enterText(find.byType(TextField).at(1), 'short');
    await tester.enterText(find.byType(TextField).at(2), 'short');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(
      find.textContaining('at least 8 characters'),
      findsOneWidget,
      reason: 'should fail locally, not wait for a 422',
    );
  });

  testWidgets('register screen rejects mismatched passwords', (tester) async {
    await tester.pumpWidget(_host(const RegisterScreen()));

    await tester.enterText(find.byType(TextField).at(0), 'someone@lcup.edu.ph');
    await tester.enterText(find.byType(TextField).at(1), 'longenoughpassword');
    await tester.enterText(find.byType(TextField).at(2), 'differentpassword');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.textContaining('do not match'), findsOneWidget);
  });

  testWidgets('verify screen shows the address and offers a resend',
      (tester) async {
    await tester.pumpWidget(_host(const VerifyOtpScreen(email: 'a@lcup.edu.ph')));

    expect(find.textContaining('a@lcup.edu.ph'), findsOneWidget);
    expect(find.text('Resend code'), findsOneWidget);
  });

  testWidgets('verify screen requires a six-character code', (tester) async {
    await tester.pumpWidget(_host(const VerifyOtpScreen(email: 'a@lcup.edu.ph')));

    await tester.enterText(find.byType(TextField).first, 'ABC');
    await tester.tap(find.text('Verify'));
    await tester.pump();

    // Matched on the error's own wording: the subtitle also mentions a
    // six-character code, so a looser matcher hits both.
    expect(find.textContaining('Enter the 6-character code'), findsOneWidget);
  });

  testWidgets('mandatory password setup offers no way back', (tester) async {
    await tester.pumpWidget(_host(const ChangePasswordScreen(mandatory: true)));

    expect(find.text('Set your password'), findsOneWidget);
    // No back arrow: the account cannot reach anything else until this is
    // done. Signing out is the only alternative.
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.text('Sign out instead'), findsOneWidget);
  });

  testWidgets('voluntary password change can be dismissed', (tester) async {
    await tester.pumpWidget(_host(const ChangePasswordScreen()));

    expect(find.text('Change password'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('Sign out instead'), findsNothing);
  });

  testWidgets('forgot password starts at the request step', (tester) async {
    await tester.pumpWidget(_host(const ForgotPasswordScreen()));

    expect(find.text('Send reset code'), findsOneWidget);
    // The code and new-password fields only appear after a code is asked
    // for, so the first step stays a single clear action.
    expect(find.text('Reset code'), findsNothing);
  });

  testWidgets('proposal letters screen states it is not wired yet',
      (tester) async {
    await tester.pumpWidget(_host(const ProposalLettersScreen()));

    expect(find.text('Proposal Letters'), findsOneWidget);
    // Honest empty state beats invented rows.
    expect(find.text('Not connected yet'), findsOneWidget);
  });
}
