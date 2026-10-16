/// Result of `POST /auth/verify-otp`, matching the backend's
/// `RegistrationVerificationOut`.
///
/// Activation and the confirmation email are separate outcomes on purpose.
/// A failed confirmation email does NOT undo a successful activation, so
/// the UI must report [confirmationEmailStatus] without telling the user
/// their registration failed.
class RegistrationResult {
  /// The backend's own human-readable message.
  final String detail;

  /// Always 'approved' when the call succeeds — registration is approved
  /// automatically once roster eligibility and the OTP both pass. There is
  /// no separate approval step to build.
  final String registrationStatus;

  final String? notificationId;

  /// 'pending' | 'sent' | 'failed', or null when the backend said nothing.
  final String? confirmationEmailStatus;

  RegistrationResult({
    required this.detail,
    required this.registrationStatus,
    required this.notificationId,
    required this.confirmationEmailStatus,
  });

  /// True when the account is active and the user can sign in, regardless
  /// of whether the confirmation email went out.
  bool get isApproved => registrationStatus == 'approved';

  /// The confirmation email did not send. Worth showing as a note, never
  /// as a registration failure.
  bool get confirmationEmailFailed => confirmationEmailStatus == 'failed';

  factory RegistrationResult.fromJson(Map<String, dynamic> json) {
    return RegistrationResult(
      detail: json['detail'] as String? ?? 'Registration verified.',
      registrationStatus: json['registration_status'] as String? ?? 'approved',
      notificationId: json['notification_id'] as String?,
      confirmationEmailStatus: json['confirmation_email_status'] as String?,
    );
  }
}
