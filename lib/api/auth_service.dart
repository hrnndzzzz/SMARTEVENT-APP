import 'api_client.dart';
import 'models/user_profile.dart';

/// Real backend auth. Two things worth knowing, confirmed directly
/// from the backend's actual code:
///   1. Login is OAuth2 form-encoded, NOT JSON — email goes in a field
///      literally named "username".
///   2. Login only returns a token, no user info — a separate
///      GET /auth/me call is required to get the signed-in user's
///      profile (including their role).
class AuthService {
  final ApiClient _client;
  AuthService(this._client);

  Future<String> login({required String email, required String password}) async {
    final formBody = 'username=${Uri.encodeQueryComponent(email)}'
        '&password=${Uri.encodeQueryComponent(password)}';

    final response = await _client.post('/auth/login', body: formBody, isForm: true);
    final token = response['access_token'] as String;
    _client.setToken(token);
    return token;
  }

  Future<UserProfile> getCurrentUser() async {
    final response = await _client.get('/auth/me');
    return UserProfile.fromJson(response as Map<String, dynamic>);
  }

  /// Admin-only. Matches POST /auth/register — requires the caller's
  /// token (set via a prior login) to belong to an Admin account,
  /// enforced server-side, not just client-side.
  Future<UserProfile> registerUser({
    required String fullName,
    required String email,
    required String password,
    required String role,
    String? position,
  }) async {
    final response = await _client.post('/auth/register', body: {
      'full_name': fullName,
      'email': email,
      'password': password,
      'role': role,
      if (position != null) 'position': position,
    });
    return UserProfile.fromJson(response as Map<String, dynamic>);
  }

  void logout() {
    _client.setToken(null);
  }
}