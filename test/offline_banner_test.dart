import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/widgets/offline_banner.dart';

Future<void> _pump(WidgetTester tester, AppState app, Reachability net) {
  final key = GlobalKey<NavigatorState>();
  return tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: net),
      ],
      child: MaterialApp(
        navigatorKey: key,
        builder: (_, child) => OfflineBanner(navigatorKey: key, child: child!),
        home: const Scaffold(body: Text('Records')),
      ),
    ),
  );
}

void main() {
  testWidgets('offline viewing shows no bar: the connection pill says it', (
    tester,
  ) async {
    final app = AppState(apiClient: ApiClient()..readOnly = true)
      ..devQuickLogin(UserRole.officer);
    final net = Reachability();
    addTearDown(app.dispose);
    addTearDown(net.dispose);
    await _pump(tester, app, net);

    expect(find.text('Records'), findsOneWidget);
    expect(find.textContaining('Offline'), findsNothing);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('a session that needs its password says so once the server answers', (
    tester,
  ) async {
    final api = ApiClient()
      ..readOnly = true
      ..requiresSignIn = true;
    final app = AppState(apiClient: api)..devQuickLogin(UserRole.officer);
    final net = Reachability();
    addTearDown(app.dispose);
    addTearDown(net.dispose);
    net.report(reachable: false);
    await _pump(tester, app, net);
    expect(find.text('Sign in'), findsNothing, reason: 'still offline');

    net.report(reachable: true);
    await tester.pump();
    expect(find.text('Sign in again to save changes.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
