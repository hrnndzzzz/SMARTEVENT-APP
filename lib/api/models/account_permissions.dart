/// What the signed-in account may actually do, as `/auth/permissions`
/// reports it.
///
/// The app used to decide this entirely from [role], which is a copy of
/// the backend's policy kept in two places — and the copies drifted. The
/// backend's hierarchy work makes financial recording Treasurer-only and
/// lets an Officer who is President, Vice President or Secretary propose
/// events, neither of which a role name can express.
///
/// So the server is asked instead. The two capability flags are nullable
/// on purpose: a backend that predates them sends neither, and the right
/// reading of a missing flag is "this server has no opinion", not "no".
/// Treating absence as a denial would lock the app against every backend
/// older than the hierarchy change.
class AccountPermissions {
  const AccountPermissions({
    required this.role,
    this.position,
    this.canProposeEvents,
    this.canRecordFinance,
    this.scope = '',
    this.responsibility = '',
    this.permissions = const [],
  });

  /// The wire role, for checking this really belongs to the account the
  /// app thinks is signed in.
  final String role;

  /// Job title. It is part of the answer now rather than decoration:
  /// which Officers may propose is decided by this.
  final String? position;

  /// Null when the backend does not say. Callers fall back to the role's
  /// built-in default rather than refusing.
  final bool? canProposeEvents;
  final bool? canRecordFinance;

  /// Descriptive, for the role card in Settings. Never gate on these.
  final String scope;
  final String responsibility;
  final List<String> permissions;

  factory AccountPermissions.fromJson(Map<String, dynamic> json) =>
      AccountPermissions(
        role: (json['role'] as String?) ?? '',
        position: json['position'] as String?,
        // Only a real boolean counts. A string or a number here means the
        // contract moved and guessing which way would be worse than
        // falling back to the role.
        canProposeEvents: json['can_propose_events'] is bool
            ? json['can_propose_events'] as bool
            : null,
        canRecordFinance: json['can_record_finance'] is bool
            ? json['can_record_finance'] as bool
            : null,
        scope: (json['scope'] as String?) ?? '',
        responsibility: (json['responsibility'] as String?) ?? '',
        permissions: [
          for (final line in (json['permissions'] as List? ?? const []))
            if (line is String) line,
        ],
      );

  /// Whether this says anything the role does not already imply.
  bool get hasCapabilityFlags =>
      canProposeEvents != null || canRecordFinance != null;
}
