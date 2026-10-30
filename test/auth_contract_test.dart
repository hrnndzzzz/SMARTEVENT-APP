import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartevent/api/admin_service.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/state/app_state.dart';

/// The bodies here are what `app/routers/auth.py` actually sends, not
/// what the app would like it to send.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = {
    'id': 'u1',
    'full_name': 'Ana Reyes',
    'email': 'ana@example.com',
    'role': 'treasurer',
    'position': null,
    'department_id': 'd1',
    'organization_id': 'o1',
    'is_active': true,
    'is_suspended': false,
    'must_change_password': false,
    'created_at': '2026-10-01T00:00:00Z',
  };

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  test('registration succeeds on the message-only reply', () async {
    final app = AppState(
      apiClient: ApiClient(
        httpClient: MockClient(
          (_) async => json({
            'detail': 'Check your email for a registration verification code.',
            'is_active': false,
          }, 201),
        ),
      ),
    );
    addTearDown(app.dispose);

    expect(
      await app.register(email: 'ana@example.com', password: 'Password-123'),
      isNull,
    );
  });

  test('a Super Admin can create a signatory account', () async {
    final sent = <http.Request>[];
    final admin = AdminService(
      ApiClient(
        httpClient: MockClient((request) async {
          sent.add(request);
          return json({...profile, 'role': 'signatory'}, 201);
        }),
      ),
    );

    final created = await admin.createSchoolReviewer(
      role: UserRole.signatory,
      fullName: 'Dr. Cruz',
      email: 'cruz@example.com',
    );

    expect(sent.single.url.path, '/auth/register/signatory');
    expect(jsonDecode(sent.single.body), {
      'full_name': 'Dr. Cruz',
      'email': 'cruz@example.com',
    });
    expect(created.role, 'signatory');
  });

  test('a password change signs in again with the new password', () async {
    final sent = <http.Request>[];
    final api = ApiClient(
      httpClient: MockClient((request) async {
        sent.add(request);
        return switch (request.url.path) {
          '/auth/change-password' => json(profile),
          '/auth/login' => json({
            'access_token': 'fresh',
            'token_type': 'bearer',
            'must_change_password': false,
          }),
          // The old token is revoked by the change.
          _ when request.headers['Authorization'] != 'Bearer fresh' => json({
            'detail': 'Could not validate credentials',
          }, 401),
          _ => json({'detail': 'Not Found'}, 404),
        };
      }),
    );
    await api.setToken('old');
    final app = AppState(apiClient: api);
    addTearDown(app.dispose);

    final error = await app.changePassword(
      currentPassword: 'Old-password-1',
      newPassword: 'New-password-1',
    );

    expect(error, isNull);
    expect(app.currentAccount?.email, 'ana@example.com');
    final login = sent.singleWhere((r) => r.url.path == '/auth/login');
    expect(login.body, contains('password=New-password-1'));
    final later = sent.skipWhile((r) => r.url.path != '/auth/login').skip(1);
    expect(later, isNotEmpty);
    expect(
      later.every((r) => r.headers['Authorization'] == 'Bearer fresh'),
      isTrue,
    );
  });
}
