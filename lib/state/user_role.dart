/// The six roles the backend enforces, mirroring `Role` in
/// `smartevent-backend/app/schemas.py` and the policy in
/// `app/rbac_policy.py`.
///
/// Listed from least to most authority. The app previously knew only
/// officer/adviser/admin and mapped `super_admin` onto admin, which meant
/// Treasurer and SDS Staff accounts had nowhere to land at all.
enum UserRole { officer, treasurer, adviser, sdsStaff, admin, superAdmin }

/// Wire format and display text.
///
/// `UserRole.name` is not usable on the wire: Dart spells two of these in
/// camelCase while the API uses snake_case.
extension UserRoleNaming on UserRole {
  /// The exact string the API sends and expects.
  String get wireName => switch (this) {
        UserRole.officer => 'officer',
        UserRole.treasurer => 'treasurer',
        UserRole.adviser => 'adviser',
        UserRole.sdsStaff => 'sds_staff',
        UserRole.admin => 'admin',
        UserRole.superAdmin => 'super_admin',
      };

  String get label => switch (this) {
        UserRole.officer => 'Officer',
        UserRole.treasurer => 'Treasurer',
        UserRole.adviser => 'Adviser',
        UserRole.sdsStaff => 'SDS Staff',
        UserRole.admin => 'Admin',
        UserRole.superAdmin => 'Super Admin',
      };

  /// One-line description of what the role is for, matching the backend's
  /// own `ROLE_POLICY` responsibilities.
  String get responsibility => switch (this) {
        UserRole.officer => 'View organization records for monitoring.',
        UserRole.treasurer => 'Record financial activity and inventory movements.',
        UserRole.adviser => 'Review event proposals and expense submissions.',
        UserRole.sdsStaff => 'View submitted proposal letters for school oversight.',
        UserRole.admin => 'Organization administrator appointed by the Super Admin.',
        UserRole.superAdmin =>
          'Designated school IT administrator, appointed by the institution.',
      };
}

/// Roles an ordinary member account can hold.
///
/// Admin and SDS Staff accounts are not created this way — they come from
/// dedicated Super Admin endpoints (`POST /auth/register/admin` and
/// `/auth/register/sds`) that issue a temporary password instead of taking
/// one, and an Admin may not create either.
const List<UserRole> memberRoles = [
  UserRole.officer,
  UserRole.treasurer,
  UserRole.adviser,
];

/// Parses a role string from the API.
///
/// Returns null for anything unrecognized rather than defaulting. The old
/// code fell back to Officer for unknown values, which silently granted a
/// guessed permission set to an account the app doesn't actually
/// understand — better to refuse the sign-in and say so.
UserRole? userRoleFromWire(String value) => switch (value) {
      'officer' => UserRole.officer,
      'treasurer' => UserRole.treasurer,
      'adviser' => UserRole.adviser,
      'sds_staff' => UserRole.sdsStaff,
      'admin' => UserRole.admin,
      'super_admin' => UserRole.superAdmin,
      _ => null,
    };

/// What each role may do.
///
/// These mirror `FRONTEND_README.md` §2 and the backend's `rbac_policy.py`.
/// They decide what the UI *offers* — the API remains the authority and can
/// still refuse, so a 403 must always be handled rather than assumed
/// impossible. Hiding a button is UX, not security.
extension UserRoleCapabilities on UserRole {
  /// Admin or Super Admin. Super Admin inherits Admin's route privileges
  /// and adds school-wide setup on top.
  bool get isAdministrator => this == UserRole.admin || this == UserRole.superAdmin;

  /// Officers read everything operational and write nothing. Their own
  /// password change and marking their own notifications read still work.
  bool get isOperationalReadOnly => this == UserRole.officer;

  /// SDS Staff is isolated to proposal letters: no dashboard, events,
  /// finance, inventory, reports or administrative screens.
  bool get isLetterOnly => this == UserRole.sdsStaff;

  /// Reaches the operational app at all.
  bool get hasOperationalAccess => !isLetterOnly;

  /// Create, edit and delete categories and the inventory catalog.
  bool get canManageCatalog => isAdministrator;

  /// Propose events. Officers cannot; SDS has no event access.
  bool get canProposeEvents =>
      this == UserRole.treasurer || this == UserRole.adviser || isAdministrator;

  /// Record income and expenses. Adviser is deliberately excluded: the
  /// whole point of the split is that whoever records the money is not the
  /// one who reviews it.
  bool get canRecordFinance => this == UserRole.treasurer || isAdministrator;

  /// Approve or reject others' submissions. Never your own — that is a
  /// separate per-record check the API enforces.
  bool get canReview => this == UserRole.adviser || isAdministrator;

  /// Record inventory stock movements (issue, return, disposal, …).
  bool get canRecordInventoryMovements =>
      this == UserRole.treasurer || this == UserRole.adviser || isAdministrator;

  /// Read and upload proposal letters. Officers have no access at all.
  bool get canAccessProposalLetters => this != UserRole.officer;

  /// Manage the approved roster and member account access, within scope.
  bool get canManageMembers => isAdministrator;

  /// Create departments, organizations, organization Admins and SDS
  /// accounts, and transfer accounts between organizations.
  bool get canAdministerSchool => this == UserRole.superAdmin;

  /// View the audit log (Admin scoped, Super Admin global).
  bool get canViewAuditLog => isAdministrator;

  /// Any operational write at all. Useful for a single "read-only account"
  /// banner rather than checking each capability separately.
  bool get canWriteAnything =>
      canProposeEvents ||
      canRecordFinance ||
      canManageCatalog ||
      canRecordInventoryMovements;
}
