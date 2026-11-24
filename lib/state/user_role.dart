/// The five roles the backend enforces, mirroring `Role` in
/// `smartevent-backend/app/schemas.py` and the policy in
/// `app/rbac_policy.py`.
///
/// Listed from least to most authority. Treasurer and Signatory were
/// removed before the November defence: a treasurer is an officer who
/// happens to hold that position, which lives in `position` rather than
/// here, and institutional signatories sign the printed form instead of
/// reviewing in the app.
enum UserRole { officer, adviser, sdsStaff, admin, superAdmin }

/// Wire format and display text.
///
/// `UserRole.name` is not usable on the wire: Dart spells two of these in
/// camelCase while the API uses snake_case.
extension UserRoleNaming on UserRole {
  /// The exact string the API sends and expects.
  String get wireName => switch (this) {
    UserRole.officer => 'officer',
    UserRole.adviser => 'adviser',
    UserRole.sdsStaff => 'sds_staff',
    UserRole.admin => 'admin',
    UserRole.superAdmin => 'super_admin',
  };

  String get label => switch (this) {
    UserRole.officer => 'Officer',
    UserRole.adviser => 'Adviser',
    UserRole.sdsStaff => 'SDS Staff',
    UserRole.admin => 'Admin',
    UserRole.superAdmin => 'Super Admin',
  };

  /// One-line description of what the role is for, matching the backend's
  /// own `ROLE_POLICY` responsibilities.
  String get responsibility => switch (this) {
    UserRole.officer =>
      'Propose events, record financial activity and inventory movements.',
    UserRole.adviser => 'Review event proposals and expense submissions.',
    UserRole.sdsStaff =>
      'View submitted proposal letters for school oversight.',
    UserRole.admin =>
      'Organization administrator appointed by the Super Admin.',
    UserRole.superAdmin =>
      'Designated school IT administrator, appointed by the institution.',
  };
}

/// Roles an ordinary member account of an organization can hold.
const List<UserRole> memberRoles = [UserRole.officer, UserRole.adviser];

/// Every role the roster and `PATCH /users/{id}/access` accept. Super
/// Admin is absent on purpose: no roster row or upload can create one.
const List<UserRole> rosterRoles = [
  ...memberRoles,
  UserRole.admin,
  UserRole.sdsStaff,
];

/// Roles [role] may put on the roster or assign to an account, mirroring
/// `manageable_roles` in the backend's `rbac_policy.py`. An Adviser manages
/// the students of their own organization, not fellow Advisers.
List<UserRole> manageableRolesFor(UserRole? role) => switch (role) {
  UserRole.superAdmin => rosterRoles,
  UserRole.admin => memberRoles,
  UserRole.adviser => const [UserRole.officer],
  _ => const [],
};

/// Parses a role string from the API.
///
/// Returns null for anything unrecognized rather than defaulting. The old
/// code fell back to Officer for unknown values, which silently granted a
/// guessed permission set to an account the app doesn't actually
/// understand — better to refuse the sign-in and say so.
UserRole? userRoleFromWire(String value) => switch (value) {
  'officer' => UserRole.officer,
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
  bool get isAdministrator =>
      this == UserRole.admin || this == UserRole.superAdmin;

  /// SDS Staff is isolated to proposal letters: no dashboard, events,
  /// finance, inventory, reports or administrative screens.
  bool get isLetterOnly => this == UserRole.sdsStaff;

  /// Reaches the operational app at all.
  bool get hasOperationalAccess => !isLetterOnly;

  /// An SDS Staff account belongs to the school, not to any department or
  /// organization.
  bool get isSchoolWide => isLetterOnly;

  /// Admin, Super Admin, or an Adviser within their own organization.
  bool get managesOrganization => isAdministrator || this == UserRole.adviser;

  /// Create, edit and delete categories and the inventory catalog.
  bool get canManageCatalog => managesOrganization;

  /// Propose events. SDS has no event access.
  bool get canProposeEvents =>
      this == UserRole.officer || this == UserRole.adviser || isAdministrator;

  /// Add and remove inventory items. Editing an item stays with
  /// [canManageCatalog].
  bool get canAddRemoveInventoryItems =>
      managesOrganization || this == UserRole.officer;

  /// Record income and expenses. Officers record; the Adviser and the Dean
  /// review. The Super Admin, the system administrator, may do both.
  /// Mirrors `can_record_finance` in the backend.
  bool get canRecordFinance =>
      this == UserRole.officer || this == UserRole.superAdmin;

  /// Approve or reject others' submissions. Never your own — that is a
  /// separate per-record check the API enforces.
  bool get canReview => this == UserRole.adviser || isAdministrator;

  /// Record inventory stock movements (issue, return, disposal, …).
  bool get canRecordInventoryMovements =>
      this == UserRole.officer || this == UserRole.adviser || isAdministrator;

  /// Read and upload proposal letters. Officers have no access at all.
  bool get canAccessProposalLetters => this != UserRole.officer;

  /// Manage the approved roster and member account access, within scope.
  bool get canManageMembers => managesOrganization;

  /// Create departments, organizations, organization Admins and SDS
  /// accounts, and transfer accounts between organizations.
  bool get canAdministerSchool => this == UserRole.superAdmin;

  /// View the audit log (Adviser: organization, Admin: department, Super
  /// Admin: global).
  bool get canViewAuditLog => managesOrganization;

  /// Any operational write at all. Useful for a single "read-only account"
  /// banner rather than checking each capability separately.
  bool get canWriteAnything =>
      canProposeEvents ||
      canRecordFinance ||
      canManageCatalog ||
      canRecordInventoryMovements;
}
