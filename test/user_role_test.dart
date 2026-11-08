import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/app_areas.dart';
import 'package:smartevent/state/app_state.dart';
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
        expect(
          userRoleFromWire(role.wireName),
          role,
          reason: '${role.name} did not round-trip',
        );
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

  group('officer proposes events, handles stock and records money', () {
    const officer = UserRole.officer;

    test('reaches operational screens', () {
      expect(officer.hasOperationalAccess, isTrue);
    });

    test('proposes, moves stock, records money, but never reviews', () {
      expect(officer.canRecordInventoryMovements, isTrue);
      expect(officer.canWriteAnything, isTrue);
      expect(officer.canProposeEvents, isTrue);
      expect(officer.canAddRemoveInventoryItems, isTrue);
      expect(officer.canRecordFinance, isTrue);
      expect(officer.canManageCatalog, isFalse);
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

    test('manages its organization like the Dean', () {
      expect(adviser.canManageCatalog, isTrue);
      expect(adviser.canManageMembers, isTrue);
      expect(adviser.canViewAuditLog, isTrue);
      expect(adviser.canAdministerSchool, isFalse);
    });

    test('manages officers and treasurers, not fellow advisers', () {
      expect(manageableRolesFor(adviser), [
        UserRole.officer,
        UserRole.treasurer,
      ]);
    });
  });

  group('roster roles', () {
    test('a Super Admin may put every role but Super Admin on the roster', () {
      expect(manageableRolesFor(UserRole.superAdmin), rosterRoles);
      expect(rosterRoles, isNot(contains(UserRole.superAdmin)));
      expect(
        rosterRoles,
        containsAll([UserRole.admin, UserRole.sdsStaff, UserRole.signatory]),
      );
    });

    test('a Dean keeps member roles; others manage nobody', () {
      expect(manageableRolesFor(UserRole.admin), memberRoles);
      for (final role in [
        UserRole.officer,
        UserRole.treasurer,
        UserRole.sdsStaff,
        UserRole.signatory,
        null,
      ]) {
        expect(manageableRolesFor(role), isEmpty, reason: '$role');
      }
    });

    test('only SDS Staff and Signatory are school-wide', () {
      expect(
        UserRole.values.where((r) => r.isSchoolWide),
        [UserRole.sdsStaff, UserRole.signatory],
      );
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
      expect(
        memberRoles,
        containsAll([UserRole.officer, UserRole.treasurer, UserRole.adviser]),
      );
    });

    test('excludes admin and sds, which have their own endpoints', () {
      expect(memberRoles, isNot(contains(UserRole.admin)));
      expect(memberRoles, isNot(contains(UserRole.superAdmin)));
      expect(memberRoles, isNot(contains(UserRole.sdsStaff)));
    });
  });

  group('what each role is offered', () {
    test('an officer is not offered letters it can never read', () {
      final ids = areasFor(UserRole.officer).map((a) => a.id);
      expect(ids, isNot(contains('letters')));
      expect(ids, isNot(contains('admin')));
      // Officers do read operational records, so these stay.
      expect(ids, containsAll(['events', 'money', 'inventory', 'reports']));
    });

    test('no role is offered the Letters menu entry', () {
      for (final role in UserRole.values) {
        expect(
          menuAreasFor(role).map((a) => a.id),
          isNot(contains('letters')),
          reason: role.name,
        );
      }
    });

    test('only administrators are offered administration', () {
      for (final role in UserRole.values) {
        final offered = areasFor(role).map((a) => a.id).contains('admin');
        expect(offered, role.canManageMembers, reason: role.name);
      }
    });

    test('roles without operational access are offered no areas', () {
      // The backend refuses both of these operational data outright, so
      // a menu entry could only ever open on a 403.
      expect(areasFor(UserRole.sdsStaff), isEmpty);
      expect(areasFor(UserRole.signatory), isEmpty);
      expect(areasFor(UserRole.officer), isNotEmpty);
    });

    test('every area offered to a role is one that role may read', () {
      for (final role in UserRole.values) {
        for (final area in areasFor(role)) {
          if (area.id == 'letters') {
            expect(role.canAccessProposalLetters, isTrue, reason: role.name);
          }
          if (area.id == 'admin') {
            expect(role.canManageMembers, isTrue, reason: role.name);
          }
        }
      }
    });
  });

  group('the scope line', () {
    test('omits a department this client cannot resolve', () {
      // A treasurer's account has a department, but GET /departments is
      // admin-only, so the list is empty and the id resolves to nothing.
      // "All Departments" would state the opposite of the truth.
      final app = AppState()..devQuickLogin(UserRole.treasurer);
      app.currentAccount = Account(
        name: 'Demo Treasurer',
        email: 'demo.treasurer@lcup.edu.ph',
        role: UserRole.treasurer,
        departmentId: 'a-real-uuid-the-client-cannot-resolve',
      );
      expect(app.departments, isEmpty);
      expect(app.departmentLabel, isNull);
    });

    test('says nothing when the account genuinely has no department', () {
      final app = AppState()..devQuickLogin(UserRole.superAdmin);
      expect(app.currentAccount!.departmentId, isNull);
      expect(app.departmentLabel, isNull);
    });
  });
}
