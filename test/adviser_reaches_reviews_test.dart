import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/screens/home_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/user_role.dart';
import 'package:smartevent/theme/app_theme.dart';

/// The adviser is not held out of the app the way SDS was — it reaches
/// everything operational. What it needs is to be told there is
/// something waiting, and a way to it.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(AppState app) => ChangeNotifierProvider.value(
    value: app,
    child: const MaterialApp(home: Scaffold(body: AlertWidget())),
  );

  testWidgets('the adviser is told what is waiting on a decision', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final app = AppState()..enterDemo(role: UserRole.adviser);

    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('awaiting a decision'),
      findsOneWidget,
      reason: 'the seeded set has events pending review',
    );
  });

  testWidgets('and an officer, who decides nothing, is not', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final app = AppState()..enterDemo(role: UserRole.officer);

    await tester.pumpWidget(host(app));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('awaiting a decision'), findsNothing);
  });

  test('the adviser may review, and reaches the operational app', () {
    expect(UserRole.adviser.canReview, isTrue);
    expect(UserRole.adviser.hasOperationalAccess, isTrue);
    expect(UserRole.adviser.isLetterOnly, isFalse);

    // The contrast that made SDS a problem.
    expect(UserRole.sdsStaff.hasOperationalAccess, isFalse);
  });
}
