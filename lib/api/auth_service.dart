import 'api_client.dart';
import 'models/registration_result.dart';
import 'models/user_profile.dart';

/// Backend auth, matching `smartevent-backend/app/routers/auth.py`.
///
/// Two things worth knowing, confirmed from the backend's own code:
///   1. Login is OAuth2 form-encoded, NOT JSON — the email goes in a field
///      literally named "username".
///   2. Login returns only a token. A separate `GET /auth/me` is required
///      for the signed-in user's profile, including their role and scope.
///
/// Registration is roster-based: the applicant supplies an email and a
/// chosen password, and the backend takes their name, role and scope from
/// a pre-approved roster entry. The app never sends a role — that is what
/// stops arbitrary self-assignment.
class AuthService {
  final ApiClient _client;
  AuthService(this._client);

  Future<String> login({required String email, required String password}) async {
    final formBody = 'username=${Uri.encodeQueryComponent(email)}'
        '&password=${Uri.encodeQueryComponent(password)}';

    final response = await _client.post('/auth/login', body: formBody, isForm: true);
    final token = response['access_token'] as String;
    await _client.setToken(token);
    return token;
  }

  Future<UserProfile> getCurrentUser() async {
    final response = await _client.get('/auth/me');
    return UserProfile.fromJson(response as Map<String, dynamic>);
  }

  /// Role explanation for the signed-in account. Descriptive metadata for
  /// display — it is not a per-record `canEdit`/`canDelete` API, so never
  /// gate an action on it.
  Future<Map<String, dynamic>> getPermissions() async {
    final response = await _client.get('/auth/permissions');
    return (response as Map).cast<String, dynamic>();
  }

  /// `POST /auth/register` — roster-based self-registration.
  ///
  /// The email must match an approved roster entry; name, role and scope
  /// come from that record. The account starts inactive until the OTP is
  /// verified, so the next screen is Verify Email, never a dashboard.
  Future<UserProfile> register({
    required String email,
    required String password,
  }) async {
    final response = await _client.post('/auth/register', body: {
      'email': email,
      'password': password,
    });
    return UserProfile.fromJson(response as Map<String, dynamic>);
  }

  /// `POST /auth/verify-otp` — activates the account.
  ///
  /// Registration approval and confirmation-email delivery are reported
  /// separately: a failed confirmation email does not undo a successful
  /// activation, so the two must not be collapsed into one message.
  Future<RegistrationResult> verifyOtp({
    required String email,
    required String otpCode,
  }) async {
    final response = await _client.post('/auth/verify-otp', body: {
      'email': email,
      'otp_code': otpCode,
    });
    return RegistrationResult.fromJson((response as Map).cast<String, dynamic>());
  }

  /// `POST /auth/resend-otp`. An invalid or expired code must not destroy
  /// registration progress — the applicant just asks for another.
  Future<void> resendOtp({required String email}) async {
    await _client.post('/auth/resend-otp', body: {'email': email});
  }

  /// `POST /auth/change-password`. Also the mandatory first-login flow when
  /// the profile reports `must_change_password`.
  Future<UserProfile> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _client.post('/auth/change-password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    return UserProfile.fromJson(response as Map<String, dynamic>);
  }

  /// `POST /auth/forgot-password`. The response is deliberately the same
  /// whether or not the address exists; don't add client-side assumptions
  /// that would leak which accounts are real.
  Future<void> forgotPassword({required String email}) async {
    await _client.post('/auth/forgot-password', body: {'email': email});
  }

  /// `POST /auth/reset-password` — email, the six-character code, and the
  /// new password.
  Future<void> resetPassword({
    required String email,
    required String otpCode,
    required String newPassword,
  }) async {
    await _client.post('/auth/reset-password', body: {
      'email': email,
      'otp_code': otpCode,
      'new_password': newPassword,
    });
  }


  /// Clears the token in memory and in secure storage. There is no backend
  /// logout endpoint — the JWT stays valid until it expires, so the only
  /// thing to do is stop holding it.
  Future<void> logout() async {
    await _client.setToken(null);
  }
}
