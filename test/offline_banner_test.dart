import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/widgets/offline_banner.dart';

void main() {
  testWidgets(
    'saved data dates identify each module instead of implying all copies are fresh',
    (tester) async {
      final api = ApiClient()..readOnly = true;
      api.readStamps['/events'] = ReadStamp(DateTime(2026, 10, 20), true);
      api.readStamps['/expenses'] = ReadStamp(DateTime(2026, 10, 21), true);
      final app = AppState(apiClient: api)..devQuickLogin(UserRole.officer);
      addTearDown(app.dispose);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            navigatorKey: key,
            builder: (_, child) =>
                OfflineBanner(navigatorKey: key, child: child!),
            home: const Scaffold(body: Text('Records')),
          ),
        ),
      );
      expect(find.text('Saved data dates'), findsOneWidget);
      await tester.tap(find.text('Saved data dates'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Events: 2026-10-20'), findsOneWidget);
      expect(find.textContaining('Expenses: 2026-10-21'), findsOneWidget);
    },
  );
}
