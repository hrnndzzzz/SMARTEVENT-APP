import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/api/api_client.dart';

/// A dead token has to end the session rather than leave the last good
/// data on screen. Yesterday's budget, shown confidently this morning,
/// is worse than an error: the figures are real, they are wrong, and
/// nothing says which.
void main() {
  ApiClient clientReturning(int status, {void Function()? onExpired}) {
    return ApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          '{"detail":"Could not validate credentials"}',
          status,
          headers: {'content-type': 'application/json'},
        ),
      ),
      onSessionExpired: onExpired,
    );
  }

  test('a 401 on a request carrying a token reports an expired session',
      () async {
    var fired = 0;
    final client = clientReturning(401, onExpired: () => fired++);
    client.setToken('a-token');

    await expectLater(client.get('/events'), throwsA(isA<ApiException>()));
    expect(fired, 1);
  });

  test('a 401 without a token does not, since that is a failed sign-in',
      () async {
    var fired = 0;
    final client = clientReturning(401, onExpired: () => fired++);

    // No token set: this is the login route refusing a password, which
    // is a different thing entirely and must not sign anyone out.
    await expectLater(
      client.post('/auth/login', body: const {}),
      throwsA(isA<ApiException>()),
    );
    expect(fired, 0);
  });

  test('other refusals leave the session alone', () async {
    var fired = 0;
    final client = clientReturning(403, onExpired: () => fired++);
    client.setToken('a-token');

    // A 403 means this account may not do this. The token is fine.
    await expectLater(client.get('/expenses'), throwsA(isA<ApiException>()));
    expect(fired, 0);
  });

  test('a success leaves the session alone', () async {
    var fired = 0;
    final client = ApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      onSessionExpired: () => fired++,
    );
    client.setToken('a-token');

    await client.get('/events');
    expect(fired, 0);
  });
}
