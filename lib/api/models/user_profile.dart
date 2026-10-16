/// Matches the backend's `UserOut` schema (see
/// `smartevent-backend/app/schemas.py`). Field names mirror the JSON keys
/// the API actually returns.
///
/// Several fields arrived with the September 2026 backend revision:
/// `department_id`, `organization_id`, `is_suspended` and
/// `must_change_password`. They are parsed defensively so the app still
/// runs against an older backend that doesn't send them yet — scope simply
/// comes back null there, and callers treat that as "not scoped".
class UserProfile {
  final String id;
  final String fullName;
  final String email;

  /// Raw wire value — 'officer' | 'treasurer' | 'adviser' | 'sds_staff' |
  /// 'admin' | 'super_admin'. Parse it with `userRoleFromWire`.
  final String role;

  /// Job title such as President or Secretary. Purely descriptive: it never
  /// overrides [role], so a Treasurer must actually have role=treasurer.
  final String? position;

  /// Scope the account is confined to. Organizations that share a
  /// department still cannot see each other's records, so both matter.
  final String? departmentId;
  final String? organizationId;

  final bool isActive;

  /// Access revoked by an administrator. Takes effect on the next request
  /// even for a token issued earlier.
  final bool isSuspended;

  /// The account is on a temporary password and must set a real one before
  /// reaching any operational screen.
  final bool mustChangePassword;

  final DateTime createdAt;

  UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.position,
    required this.departmentId,
    required this.organizationId,
    required this.isActive,
    required this.isSuspended,
    required this.mustChangePassword,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      position: json['position'] as String?,
      departmentId: json['department_id'] as String?,
      organizationId: json['organization_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isSuspended: json['is_suspended'] as bool? ?? false,
      mustChangePassword: json['must_change_password'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
