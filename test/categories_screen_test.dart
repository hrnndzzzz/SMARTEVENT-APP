import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/categories_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Categories is the first module built to the full contract, so these
/// pin down the two things that are easy to get wrong everywhere else:
/// write controls appearing for roles that cannot write, and loading /
/// empty / failed collapsing into one indistinguishable blank screen.
Widget _host(AppState state) {
  return ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(theme: AppTheme.light(), home: const CategoriesScreen()),
  );
}

void main() {
  testWidgets('officers get no create control', (tester) async {
    final state = AppState()..devQuickLogin(UserRole.officer);
    await tester.pumpWidget(_host(state));
    await tester.pump();

    expect(find.text('New Category'), findsNothing);
  });

  testWidgets('advisers get no create control either', (tester) async {
    // Advisers review; managing the catalog is an administrator's job.
    final state = AppState()..devQuickLogin(UserRole.adviser);
    await tester.pumpWidget(_host(state));
    await tester.pump();

    expect(find.text('New Category'), findsNothing);
  });

  testWidgets('treasurers get no create control', (tester) async {
    final state = AppState()..devQuickLogin(UserRole.treasurer);
    await tester.pumpWidget(_host(state));
    await tester.pump();

    expect(find.text('New Category'), findsNothing);
  });

  testWidgets('admins do get a create control', (tester) async {
    final state = AppState()..devQuickLogin(UserRole.admin);
    await tester.pumpWidget(_host(state));
    await tester.pump();

    expect(find.text('New Category'), findsOneWidget);
  });

  testWidgets('super admins do too', (tester) async {
    final state = AppState()..devQuickLogin(UserRole.superAdmin);
    await tester.pumpWidget(_host(state));
    await tester.pump();

    expect(find.text('New Category'), findsOneWidget);
  });

  testWidgets('an empty list explains itself differently per role',
      (tester) async {
    final adminState = AppState()..devQuickLogin(UserRole.admin);
    await tester.pumpWidget(_host(adminState));
    await tester.pump();

    expect(find.text('No categories yet'), findsOneWidget);
    expect(find.textContaining('Create one to start'), findsOneWidget);

    final officerState = AppState()..devQuickLogin(UserRole.officer);
    await tester.pumpWidget(_host(officerState));
    await tester.pump();

    // An Officer cannot act on it, so pointing them at a button they do
    // not have would be useless.
    expect(find.textContaining('has not set up budget categories'),
        findsOneWidget);
  });
}
