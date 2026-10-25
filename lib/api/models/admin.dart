import '../../state/user_role.dart';

/// An approved roster entry — the backend's `CiteMemberOut`.
///
/// This is **not an account**. It is permission to create one: registration
/// matches an applicant's email against these, and takes their name, role
/// and scope from the matching row. That is what stops anyone assigning
/// themselves a role.
///
/// Once claimed, the entry is spent. It cannot be deleted, and the account
/// it produced is managed through [ManagedUser] instead.
class RosterEntry {
  final String id;
  final String fullName;
  final String email;

  /// Only ever a member role — officer, treasurer or adviser. Admin and SDS
  /// accounts are created through their own Super Admin endpoints.
  final UserRole role;

  final String? position;
  final String? departmentId;
  final String? organizationId;

  /// The account created from this entry, once someone has registered
  /// against it.
  final String? claimedByUserId;

  final DateTime createdAt;

  RosterEntry({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.position,
    required this.departmentId,
    required this.organizationId,
    required this.claimedByUserId,
    required this.createdAt,
  });

  /// Someone has registered against this entry. Claimed rows are editable
  /// only in limited ways and cannot be deleted at all — the account is
  /// what carries on from here.
  bool get isClaimed => claimedByUserId != null;

  factory RosterEntry.fromJson(Map<String, dynamic> json) {
    return RosterEntry(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      // A roster role is always a member role; anything else would be a
      // backend change worth noticing rather than silently coercing.
      role: userRoleFromWire(json['role'] as String? ?? '') ?? UserRole.officer,
      position: json['position'] as String?,
      departmentId: json['department_id'] as String?,
      organizationId: json['organization_id'] as String?,
      claimedByUserId: json['claimed_by_user_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// A registered account, as an administrator sees it — the backend's
/// `UserOut` from `GET /users`.
///
/// There is no delete endpoint, by design. An account that should lose
/// access is **suspended**, which preserves everything it did. A UI that
/// offers Delete is promising something the system deliberately refuses.
class ManagedUser {
  final String id;
  final String fullName;
  final String email;
  final UserRole? role;
  final String? position;
  final String? departmentId;
  final String? organizationId;
  final bool isActive;

  /// Access revoked. Takes effect on the next request even for a token
  /// issued before the suspension.
  final bool isSuspended;

  /// Still on a temporary password. Restoring an account does not clear
  /// this, and does not verify a registration that never completed.
  final bool mustChangePassword;

  final DateTime createdAt;

  ManagedUser({
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

  /// Signed in and working normally.
  bool get isUsable => isActive && !isSuspended;

  String get statusLabel {
    if (isSuspended) return 'Suspended';
    if (!isActive) return 'Not activated';
    if (mustChangePassword) return 'Awaiting password setup';
    return 'Active';
  }

  factory ManagedUser.fromJson(Map<String, dynamic> json) {
    return ManagedUser(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      role: userRoleFromWire(json['role'] as String? ?? ''),
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

/// One administrative action, as recorded — `AuditLogOut`.
///
/// Read-only. There is no endpoint to edit or remove an entry, which is
/// rather the point of an audit log.
class AuditEntry {
  final String id;

  /// Who did it. An id rather than a name — the backend does not resolve
  /// them, and fetching `/users` to decorate the list would be refused for
  /// anything outside the reader's own scope.
  final String? userId;

  final String? organizationId;
  final String? departmentId;

  final String action;
  final String? entityType;
  final String? entityId;

  /// Whatever the backend chose to record about the change.
  final Map<String, dynamic>? details;

  final DateTime createdAt;

  AuditEntry({
    required this.id,
    required this.userId,
    required this.organizationId,
    required this.departmentId,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.details,
    required this.createdAt,
  });

  /// "Suspended user" from "suspend_user", for a readable list.
  String get readableAction {
    final words = action.replaceAll('_', ' ').trim();
    if (words.isEmpty) return 'Unknown action';
    return words[0].toUpperCase() + words.substring(1);
  }

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      organizationId: json['organization_id'] as String?,
      departmentId: json['department_id'] as String?,
      action: json['action'] as String? ?? '',
      entityType: json['entity_type'] as String?,
      entityId: json['entity_id'] as String?,
      details: (json['details'] as Map?)?.cast<String, dynamic>(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
