import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/user_role.dart';

/// Locks the client-side capability matrix to the backend's own policy in
/// `smartevent-backend/app/rbac_policy.py` and the navigation table in
/// `FRONTEND_README.md` §2.
///
/// These decide which controls the UI offers. The API is still the
/// authority and can refuse anything, but a wrong answer here either hides
/// a control a role should have or shows one it shouldn't — the second
/// being how an Officer ends up with an Edit button that 403s.
void main() {
  group('wire format', () {
    test('every role round-trips through its wire name', () {
      for (final role in UserRole.values) {
        expect(userRoleFromWire(role.wireName), role,
            reason: '${role.name} did not round-trip');
      }
    });

    test('wire names are the snake_case the API actually sends', () {
      expect(UserRole.superAdmin.wireName, 'super_admin');
      expect(UserRole.sdsStaff.wireName, 'sds_staff');
      expect(UserRole.treasurer.wireName, 'treasurer');
    });

    test('an unrecognized role is rejected, not guessed', () {
      // The old code fell back to Officer here, silently granting a
      // guessed permission set to an account it could not model.
      expect(userRoleFromWire('registrar'), isNull);
      expect(userRoleFromWire(''), isNull);
      expect(userRoleFromWire('Admin'), isNull, reason: 'case matters');
    });
  });

  group('officer is operational read-only', () {
    const officer = UserRole.officer;

    test('reaches operational screens', () {
      expect(officer.hasOperationalAccess, isTrue);
    });

    test('writes nothing at all', () {
      expect(officer.canWriteAnything, isFalse);
      expect(officer.canProposeEvents, isFalse);
      expect(officer.canRecordFinance, isFalse);
      expect(officer.canManageCatalog, isFalse);
      expect(officer.canRecordInventoryMovements, isFalse);
      expect(officer.canReview, isFalse);
    });

    test('has no proposal-letter access', () {
      expect(officer.canAccessProposalLetters, isFalse);
    });
  });

  group('treasurer records money but never reviews it', () {
    const treasurer = UserRole.treasurer;

    test('records finance and inventory movements', () {
      expect(treasurer.canRecordFinance, isTrue);
      expect(treasurer.canRecordInventoryMovements, isTrue);
      expect(treasurer.canProposeEvents, isTrue);
    });

    test('cannot review submissions', () {
      // The separation of duties the whole role split exists for.
      expect(treasurer.canReview, isFalse);
    });

    test('cannot manage the catalog or members', () {
      expect(treasurer.canManageCatalog, isFalse);
      expect(treasurer.canManageMembers, isFalse);
    });
  });

  group('adviser reviews but does not record money', () {
    const adviser = UserRole.adviser;

    test('reviews and proposes', () {
      expect(adviser.canReview, isTrue);
      expect(adviser.canProposeEvents, isTrue);
    });

    test('does not record finance', () {
      expect(adviser.canRecordFinance, isFalse);
    });

    test('does not manage the catalog', () {
      expect(adviser.canManageCatalog, isFalse);
    });
  });

  group('administrators', () {
    test('admin and super admin both count as administrators', () {
      expect(UserRole.admin.isAdministrator, isTrue);
      expect(UserRole.superAdmin.isAdministrator, isTrue);
      for (final role in [
        UserRole.officer,
        UserRole.treasurer,
        UserRole.adviser,
        UserRole.sdsStaff,
      ]) {
        expect(role.isAdministrator, isFalse, reason: role.name);
      }
    });

    test('admin manages catalog, members and audit within scope', () {
      expect(UserRole.admin.canManageCatalog, isTrue);
      expect(UserRole.admin.canManageMembers, isTrue);
      expect(UserRole.admin.canViewAuditLog, isTrue);
      expect(UserRole.admin.canReview, isTrue);
    });

    test('only super admin administers the school', () {
      // Departments, organizations, creating Admin/SDS accounts, transfers.
      expect(UserRole.superAdmin.canAdministerSchool, isTrue);
      expect(UserRole.admin.canAdministerSchool, isFalse);
    });
  });

  group('sds staff is isolated to proposal letters', () {
    const sds = UserRole.sdsStaff;

    test('has no operational access', () {
      expect(sds.hasOperationalAccess, isFalse);
      expect(sds.isLetterOnly, isTrue);
    });

    test('reads letters', () {
      expect(sds.canAccessProposalLetters, isTrue);
    });

    test('touches no operational module', () {
      expect(sds.canProposeEvents, isFalse);
      expect(sds.canRecordFinance, isFalse);
      expect(sds.canManageCatalog, isFalse);
      expect(sds.canRecordInventoryMovements, isFalse);
      expect(sds.canReview, isFalse);
      expect(sds.canManageMembers, isFalse);
      expect(sds.canViewAuditLog, isFalse);
    });
  });

  group('assignable member roles', () {
    test('covers exactly the roles a roster entry can hold', () {
      expect(memberRoles,
          containsAll([UserRole.officer, UserRole.treasurer, UserRole.adviser]));
    });

    test('excludes admin and sds, which have their own endpoints', () {
      expect(memberRoles, isNot(contains(UserRole.admin)));
      expect(memberRoles, isNot(contains(UserRole.superAdmin)));
      expect(memberRoles, isNot(contains(UserRole.sdsStaff)));
    });
  });
}
