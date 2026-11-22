import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/main.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';

/// The dashboard walks a first sign-in through itself once, and Settings
/// can ask for it again.
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

  testWidgets('a first sign-in gets the tour, a second does not', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final app = await signIn(tester, UserRole.treasurer);
    expect(find.text('1 OF 5'), findsOneWidget);
    expect(find.text('Notices and your account'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await frames(tester);
    expect(find.text('1 OF 5'), findsNothing);

    await app.signOut();
    await frames(tester);
    await signIn(tester, UserRole.treasurer);
    expect(find.text('1 OF 5'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  // The Adviser reviews money rather than recording it.
  testWidgets('a role that records nothing skips the Record stop', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'tour.seenBy': <String>['demo'],
    });
    await signIn(tester, UserRole.adviser);
    expect(find.textContaining(' OF '), findsNothing);

    tester
        .element(find.byType(Scaffold).first)
        .read<AppSettings>()
        .tourRequests
        .value++;
    await frames(tester);
    expect(find.text('1 OF 4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
