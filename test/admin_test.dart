import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/admin.dart';
import 'package:smartevent/state/user_role.dart';

/// Roster entries and accounts are different things, and the difference
/// decides what may be done to each. Getting it wrong means either removing
/// something that governs a live account, or offering a delete the backend
/// will never honour.
RosterEntry _entry({String? claimedBy, String role = 'officer'}) {
  return RosterEntry.fromJson({
    'id': 'm1',
    'full_name': 'Jerico Reyes',
    'email': 'jerico@lcup.edu.ph',
    'role': role,
    'position': '1st Year Representative',
    'department_id': 'd1',
    'organization_id': 'o1',
    'claimed_by_user_id': claimedBy,
    'created_at': '2026-09-20T10:00:00Z',
  });
}

ManagedUser _user({
  bool active = true,
  bool suspended = false,
  bool mustChange = false,
  String role = 'treasurer',
}) {
  return ManagedUser.fromJson({
    'id': 'u1',
    'full_name': 'Sean Reyes',
    'email': 'sean@lcup.edu.ph',
    'role': role,
    'position': null,
    'department_id': 'd1',
    'organization_id': 'o1',
    'is_active': active,
    'is_suspended': suspended,
    'must_change_password': mustChange,
    'created_at': '2026-09-20T10:00:00Z',
  });
}

void main() {
  group('roster entries', () {
    test('an unclaimed entry is still free to manage', () {
      expect(_entry().isClaimed, isFalse);
    });

    test('a claimed entry is spent', () {
      // Someone registered against it; the account takes over from here.
      expect(_entry(claimedBy: 'u1').isClaimed, isTrue);
    });

    test('parses the member role it grants', () {
      expect(_entry(role: 'treasurer').role, UserRole.treasurer);
      expect(_entry(role: 'adviser').role, UserRole.adviser);
    });

    test('only member roles can be assigned through the roster', () {
      // Admin and SDS come from their own Super Admin endpoints.
      expect(memberRoles, isNot(contains(UserRole.admin)));
      expect(memberRoles, isNot(contains(UserRole.sdsStaff)));
      expect(memberRoles, isNot(contains(UserRole.superAdmin)));
    });
  });

  group('account status', () {
    test('active and unsuspended is usable', () {
      expect(_user().isUsable, isTrue);
      expect(_user().statusLabel, 'Active');
    });

    test('suspension overrides everything else', () {
      final user = _user(suspended: true);
      expect(user.isUsable, isFalse);
      expect(user.statusLabel, 'Suspended');
    });

    test('an unactivated account is not usable', () {
      final user = _user(active: false);
      expect(user.isUsable, isFalse);
      expect(user.statusLabel, 'Not activated');
    });

    test('a temporary password is surfaced rather than hidden', () {
      // Restoring access does not clear this, so it has to stay visible.
      final user = _user(mustChange: true);
      expect(user.statusLabel, 'Awaiting password setup');
      expect(user.isUsable, isTrue, reason: 'it can sign in, just not act yet');
    });

    test('an unrecognized role reads as null rather than a guess', () {
      expect(_user(role: 'registrar').role, isNull);
      expect(_user(role: 'registrar').statusLabel, 'Active');
    });
  });

  group('audit entries', () {
    AuditEntry entry({String action = 'suspend_user'}) {
      return AuditEntry.fromJson({
        'id': 'a1',
        'user_id': 'u1',
        'organization_id': 'o1',
        'department_id': 'd1',
        'action': action,
        'entity_type': 'user',
        'entity_id': 'u2',
        'details': {'reason': 'left the organization'},
        'created_at': '2026-09-20T10:00:00Z',
      });
    }

    test('makes the action readable', () {
      expect(entry(action: 'suspend_user').readableAction, 'Suspend user');
      expect(entry(action: 'create_department').readableAction,
          'Create department');
    });

    test('copes with a missing action', () {
      expect(entry(action: '').readableAction, 'Unknown action');
    });

    test('keeps the recorded details', () {
      expect(entry().details?['reason'], 'left the organization');
      expect(entry().entityType, 'user');
    });
  });
}
