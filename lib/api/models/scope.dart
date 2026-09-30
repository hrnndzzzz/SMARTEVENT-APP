/// Departments and organizations — the scope every operational record
/// belongs to.
///
/// Named `Remote*` like the other API models, and because `Department` is
/// already taken by a display-only enum in `app_state.dart` that predates
/// real departments.
///
/// Most accounts never see these: a scoped user's department and
/// organization come from `/auth/me` and the backend applies them itself. A
/// Super Admin has neither, so it must choose, which is the only reason
/// these lookups exist. Both list endpoints require Admin or above.
class RemoteDepartment {
  final String id;
  final String code;
  final String name;
  final String? description;

  RemoteDepartment({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
  });

  /// "CITE — College of Information Technology" for a picker row.
  String get label => '$code — $name';

  factory RemoteDepartment.fromJson(Map<String, dynamic> json) {
    return RemoteDepartment(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
    );
  }
}

/// An organization always belongs to exactly one department, and
/// organizations inside the same department cannot see each other's
/// records — so picking one is not a formality.
class RemoteOrganization {
  final String id;
  final String code;
  final String name;
  final String departmentId;

  RemoteOrganization({
    required this.id,
    required this.code,
    required this.name,
    required this.departmentId,
  });

  String get label => '$code — $name';

  factory RemoteOrganization.fromJson(Map<String, dynamic> json) {
    return RemoteOrganization(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      departmentId: json['department_id'] as String,
    );
  }
}
