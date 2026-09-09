/// Matches the backend's UserOut schema exactly (see
/// smartevent-backend/app/schemas.py). Field names are intentionally
/// identical to the JSON keys the API actually returns.
class UserProfile {
  final String id;
  final String fullName;
  final String email;
  final String role; // "officer" | "adviser" | "admin"
  final String? position;
  final bool isActive;
  final DateTime createdAt;

  UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.position,
    required this.isActive,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      position: json['position'] as String?,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}