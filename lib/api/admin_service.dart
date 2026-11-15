import '../state/user_role.dart';
import 'api_client.dart';
import 'models/roster_import.dart';
import 'models/admin.dart';
import 'models/scope.dart';
import 'models/user_profile.dart';

/// Roster, member accounts, scope setup and the audit log.
///
/// Three things the backend deliberately does not offer, so neither does
/// this: creating a Super Admin (that is a controlled CLI bootstrap),
/// deleting a user (suspend instead), and editing or deleting departments,
/// organizations or audit records.
class AdminService {
  final ApiClient _client;
  AdminService(this._client);

  // ---- Approved roster ---------------------------------------------------

  Future<List<RosterEntry>> roster({
    String? departmentId,
    String? organizationId,
    bool? claimed,
  }) async {
    final query = <String, String>{
      if (departmentId != null) 'department_id': departmentId,
      if (organizationId != null) 'organization_id': organizationId,
      if (claimed != null) 'claimed': claimed.toString(),
    };
    final response = await _client.get(
      '/cite-members',
      query: query.isEmpty ? null : query,
    );
    return (response as List)
        .map((json) => RosterEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Adds someone to the approved roster. This creates **no account** — it
  /// makes one possible, by letting that email register.
  ///
  /// [role] must be one the caller may manage (`manageableRolesFor`). An
  /// Admin or Adviser may omit the scope to use its own; a Super Admin
  /// chooses, except for school-wide roles, which take none.
  Future<RosterEntry> addToRoster({
    required String fullName,
    required String email,
    required UserRole role,
    String? position,
    String? departmentId,
    String? organizationId,
  }) async {
    final response = await _client.post(
      '/cite-members',
      body: {
        'full_name': fullName,
        'email': email,
        'role': role.wireName,
        if (position != null) 'position': position,
        if (departmentId != null) 'department_id': departmentId,
        if (organizationId != null) 'organization_id': organizationId,
      },
    );
    return RosterEntry.fromJson(response as Map<String, dynamic>);
  }

  /// `POST /cite-members/import` — a whole roster from one workbook.
  ///
  /// The server validates all of it before inserting any of it, so a bad
  /// row means nothing was added and every bad row is named. That comes
  /// back as [RosterImportRejected] rather than a single message,
  /// because a roster of two hundred with four bad emails needs those
  /// four pointed at.
  ///
  /// Throws [ArgumentError] when the file is one the server would refuse
  /// outright, rather than spending the upload to find out.
  Future<RosterImportResult> importRoster({
    required List<int> bytes,
    required String filename,
  }) async {
    final problem = RosterWorkbook.problemWith(filename, bytes.length);
    if (problem != null) throw ArgumentError(problem);

    try {
      final response = await _client.upload(
        '/cite-members/import',
        field: 'file',
        bytes: bytes,
        filename: filename,
        contentType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      return RosterImportResult.fromJson(response as Map<String, dynamic>);
    } on ApiException catch (error) {
      final rejected = RosterImportRejected.from(
        error.detail ?? const <String, Object?>{},
      );
      if (rejected != null) throw rejected;
      rethrow;
    }
  }

  /// Role and position only — name and email are **not** editable, because
  /// the email is what registration matches on. Moving an entry to another
  /// organization is Super Admin only.
  Future<RosterEntry> updateRosterEntry(
    String memberId, {
    UserRole? role,
    String? position,
    String? organizationId,
  }) async {
    final response = await _client.patch(
      '/cite-members/$memberId',
      body: {
        if (role != null) 'role': role.wireName,
        if (position != null) 'position': position,
        if (organizationId != null) 'organization_id': organizationId,
      },
    );
    return RosterEntry.fromJson(response as Map<String, dynamic>);
  }

  /// Unclaimed entries only. Once someone has registered against a row it
  /// cannot be removed — manage the resulting account instead.
  Future<void> removeRosterEntry(String memberId) async {
    await _client.delete('/cite-members/$memberId');
  }

  // ---- Registered accounts ----------------------------------------------

  Future<List<ManagedUser>> users({
    String? departmentId,
    String? organizationId,
    bool? isActive,
    bool? isSuspended,
  }) async {
    final query = <String, String>{
      if (departmentId != null) 'department_id': departmentId,
      if (organizationId != null) 'organization_id': organizationId,
      if (isActive != null) 'is_active': isActive.toString(),
      if (isSuspended != null) 'is_suspended': isSuspended.toString(),
    };
    final response = await _client.get(
      '/users',
      query: query.isEmpty ? null : query,
    );
    return (response as List)
        .map((json) => ManagedUser.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// `PATCH /users/{id}/access` — role, position, suspension, and transfer.
  ///
  /// An Admin changes only member roles and an Adviser only Officers and
  /// Treasurers. Neither can transfer scope,
  /// cannot change its own access and cannot touch a Super Admin. Those are
  /// enforced server-side; the UI hides what it can and handles the 403 for
  /// the rest.
  ///
  /// Suspension takes effect on the next request even for an existing
  /// token, and restoring does not bypass a pending password setup.
  Future<ManagedUser> updateAccess(
    String userId, {
    UserRole? role,
    String? position,
    bool? isSuspended,
    String? organizationId,
  }) async {
    final response = await _client.patch(
      '/users/$userId/access',
      body: {
        if (role != null) 'role': role.wireName,
        if (position != null) 'position': position,
        if (isSuspended != null) 'is_suspended': isSuspended,
        if (organizationId != null) 'organization_id': organizationId,
      },
    );
    return ManagedUser.fromJson(response as Map<String, dynamic>);
  }

  // ---- Scope setup, Super Admin only ------------------------------------

  Future<RemoteDepartment> createDepartment({
    required String code,
    required String name,
    String? description,
  }) async {
    final response = await _client.post(
      '/departments',
      body: {
        'code': code,
        'name': name,
        if (description != null) 'description': description,
      },
    );
    return RemoteDepartment.fromJson(response as Map<String, dynamic>);
  }

  /// [departmentId] null for an organization outside any department.
  Future<RemoteOrganization> createOrganization({
    required String code,
    required String name,
    String? departmentId,
  }) async {
    final response = await _client.post(
      '/organizations',
      body: {
        'code': code,
        'name': name,
        if (departmentId != null) 'department_id': departmentId,
      },
    );
    return RemoteOrganization.fromJson(response as Map<String, dynamic>);
  }

  /// Creates an organization Admin. No password is sent — the backend
  /// issues a temporary one by email, so this fails if email is not
  /// configured.
  Future<UserProfile> createAdmin({
    required String fullName,
    required String email,
    required String organizationId,
    required String departmentId,
    String? position,
  }) async {
    final response = await _client.post(
      '/auth/register/admin',
      body: {
        'full_name': fullName,
        'email': email,
        'organization_id': organizationId,
        'department_id': departmentId,
        if (position != null) 'position': position,
      },
    );
    return UserProfile.fromJson(response as Map<String, dynamic>);
  }

  /// SDS Staff or a Signatory: school accounts with no organization.
  Future<UserProfile> createSchoolReviewer({
    required UserRole role,
    required String fullName,
    required String email,
    String? position,
  }) async {
    final response = await _client.post(
      role == UserRole.signatory
          ? '/auth/register/signatory'
          : '/auth/register/sds',
      body: {
        'full_name': fullName,
        'email': email,
        if (position != null) 'position': position,
      },
    );
    return UserProfile.fromJson(response as Map<String, dynamic>);
  }

  // ---- Audit -------------------------------------------------------------

  /// Read-only history. Admin sees its own scope, Super Admin everything.
  Future<List<AuditEntry>> auditLog({int limit = 50, int offset = 0}) async {
    final response = await _client.get(
      '/audit-logs',
      query: {'limit': limit.toString(), 'offset': offset.toString()},
    );
    return (response as List)
        .map((json) => AuditEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
