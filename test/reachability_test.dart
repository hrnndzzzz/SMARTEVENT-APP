import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/widgets/connection_banner.dart';

/// What the app claims about the backend before it has asked it anything.
///
/// It used to claim "Online · The server is answering" from a standing
/// start, which in the demo — where no request is ever made — it said
/// for the whole session about a server it had never contacted.
Widget host(Reachability reach, Widget child) => ChangeNotifierProvider.value(
  value: reach,
  child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
);

void main() {
  test('nothing is known until something has been asked', () {
    final reach = Reachability();

    expect(reach.state, Reachable.unknown);
    expect(reach.isOnline, isFalse, reason: 'nothing has answered yet');
    expect(reach.offlineFor, isNull);
  });

  test('a request that got through is what makes it online', () {
    final reach = Reachability()..report(reachable: true);

    expect(reach.state, Reachable.online);
    expect(reach.isOnline, isTrue);
  });

  test('a request that did not get through makes it offline', () {
    final reach = Reachability()..report(reachable: false);

    expect(reach.state, Reachable.offline);
    expect(reach.offlineFor, isNotNull);
  });

  test('opening the app asks the server instead of waiting', () async {
    var asked = 0;
    final reach = Reachability(
      httpClient: MockClient((_) async {
        asked++;
        return http.Response('ok', 200);
      }),
    );

    await Future.wait([reach.wake(), reach.wake()]);

    expect(reach.state, Reachable.online);
    expect(asked, 1, reason: 'a second open while one is asking waits');
    // A stale "online" from before the app was put away is asked again.
    await reach.wake();
    expect(asked, 2);
    reach.dispose();
  });

  test('a server that does not answer the wake-up is offline', () async {
    final reach = Reachability(
      httpClient: MockClient((_) async => throw http.ClientException('down')),
    );

    await reach.wake();

    expect(reach.state, Reachable.offline);
    reach.dispose();
  });

  testWidgets('the dot shows nothing while nothing is known', (tester) async {
    await tester.pumpWidget(host(Reachability(), const ConnectionDot()));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(ConnectionDot));
    expect(size, Size.zero, reason: 'no claim to make, so no dot');
  });

  testWidgets('and shows one once the server has answered', (tester) async {
    final reach = Reachability()..report(reachable: true);

    await tester.pumpWidget(host(reach, const ConnectionDot(size: 10)));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(ConnectionDot)).width, 10);
  });
}
