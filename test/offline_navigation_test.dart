import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/main.dart';
import 'package:smartevent/state/app_state.dart';

void main() {
  testWidgets(
    'signing out closes routes holding the previous account records',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const SmartEventApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final app = tester.element(find.byType(Scaffold).first).read<AppState>();
      app.enterDemo(role: UserRole.officer);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Text('Previous account private record')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Previous account private record'), findsOneWidget);
      await app.signOut();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Previous account private record'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
