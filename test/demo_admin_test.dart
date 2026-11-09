import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/admin.dart';
import 'package:smartevent/state/app_state.dart';

/// The administrator's screens, in the demo.
///
/// These had no demo branch at all: every one of them called a backend
/// the demo has no token for, so the roster, the accounts and the audit
/// log all came up as errors. They are the screens where the
/// permissions actually live, which makes them the ones a panel is most
/// likely to ask to see.
///
/// What is asserted throughout is that an action *changed something* —
/// a branch that returns null and leaves the list alone passes a test
/// that only checks for the absence of an error, and looks broken on
/// the phone.
void main() {
  Future<AppState> admin() async {
    final app = AppState()..enterDemo(role: UserRole.admin);
    await app.loadRoster();
    await app.loadManagedUsers();
    await app.loadAuditLog();
    return app;
  }

  group('what loads', () {
    test('the roster, the accounts and the log all arrive', () async {
      final app = await admin();

      expect(app.roster, isNotEmpty);
      expect(app.managedUsers, isNotEmpty);
      expect(app.auditLog, isNotEmpty);
    });

    test('no load reports a failure', () async {
      final app = await admin();

      expect(app.rosterLoad.error, isNull);
      expect(app.usersLoad.error, isNull);
      expect(app.auditLoad.error, isNull);
    });

    test('the roster has both claimed and unclaimed rows', () async {
      final app = await admin();

      expect(app.unclaimedRoster, isNotEmpty);
      expect(
        app.roster.where((r) => r.isClaimed),
        isNotEmpty,
        reason: 'a roster where every row behaves the same demonstrates '
            'nothing about the rule that claimed rows are frozen',
      );
    });

    test('the accounts cover more than one status', () async {
      final app = await admin();

      expect(
        app.managedUsers.map((u) => u.statusLabel).toSet().length,
        greaterThan(1),
      );
    });
  });

  group('the roster', () {
    test('adding puts the entry at the top, unclaimed', () async {
      final app = await admin();
      final before = app.roster.length;

      final error = await app.addRosterEntry(
        fullName: 'Nina Robles',
        email: 'nina.robles@lcup.edu.ph',
        role: UserRole.officer,
        organizationId: 'demo-acpes',
        departmentId: 'demo-cite',
      );

      expect(error, isNull);
      expect(app.roster, hasLength(before + 1));
      expect(app.roster.first.fullName, 'Nina Robles');
      expect(app.roster.first.isClaimed, isFalse);
    });

    test('editing changes the row and nothing else', () async {
      final app = await admin();
      final entry = app.unclaimedRoster.first;

      final error = await app.updateRosterEntry(
        entry,
        role: UserRole.treasurer,
        position: 'Acting Treasurer',
      );

      expect(error, isNull);
      final after = app.roster.firstWhere((r) => r.id == entry.id);
      expect(after.role, UserRole.treasurer);
      expect(after.position, 'Acting Treasurer');
      expect(after.email, entry.email, reason: 'nothing else should move');
    });

    test('removing an unclaimed entry takes it off the list', () async {
      final app = await admin();
      final entry = app.unclaimedRoster.first;

      final error = await app.removeRosterEntry(entry);

      expect(error, isNull);
      expect(app.roster.map((r) => r.id), isNot(contains(entry.id)));
    });

    test('a claimed entry is refused, and stays', () async {
      final app = await admin();
      final claimed = app.roster.firstWhere((r) => r.isClaimed);

      final error = await app.removeRosterEntry(claimed);

      expect(error, isNotNull);
      expect(app.roster.map((r) => r.id), contains(claimed.id));
    });

    test('an import says plainly that it read nothing', () async {
      final app = await admin();
      final before = app.roster.length;

      final result = await app.importRoster(
        bytes: const [1, 2, 3],
        filename: 'members.xlsx',
      );

      expect(result.insertedCount, 0);
      expect(
        app.roster,
        hasLength(before),
        reason: 'inventing rows from a workbook nobody parsed would be a '
            'worse demo than admitting it was not read',
      );
    });
  });

  group('accounts', () {
    ManagedUser other(AppState app) =>
        app.managedUsers.firstWhere((u) => u.id != app.currentAccount?.id);

    test('suspending shows the account suspended', () async {
      final app = await admin();
      final user = other(app);

      final error = await app.setUserSuspended(user, true);

      expect(error, isNull);
      final after = app.managedUsers.firstWhere((u) => u.id == user.id);
      expect(after.isSuspended, isTrue);
      expect(after.statusLabel, 'Suspended');
    });

    test('restoring puts it back', () async {
      final app = await admin();
      final user = app.managedUsers.firstWhere((u) => u.isSuspended);

      await app.setUserSuspended(user, false);

      final after = app.managedUsers.firstWhere((u) => u.id == user.id);
      expect(after.isSuspended, isFalse);
    });

    test('a role change sticks', () async {
      final app = await admin();
      final user = other(app);

      final error = await app.updateUserAccess(user, role: UserRole.adviser);

      expect(error, isNull);
      expect(
        app.managedUsers.firstWhere((u) => u.id == user.id).role,
        UserRole.adviser,
      );
    });

    test('a new privileged account lands awaiting its password', () async {
      final app = await admin();
      final before = app.managedUsers.length;

      final error = await app.createPrivilegedAccount(
        role: UserRole.sdsStaff,
        fullName: 'Grace Lumibao',
        email: 'grace.lumibao@lcup.edu.ph',
      );

      expect(error, isNull);
      expect(app.managedUsers, hasLength(before + 1));
      expect(
        app.managedUsers.last.statusLabel,
        'Awaiting password setup',
        reason: 'no invitation email leaves the device in the demo, so the '
            'account must not look as though one did',
      );
    });

    test('an Admin without a department is still refused', () async {
      final app = await admin();
      final before = app.managedUsers.length;

      final error = await app.createPrivilegedAccount(
        role: UserRole.admin,
        fullName: 'Someone',
        email: 'someone@lcup.edu.ph',
      );

      expect(error, isNotNull);
      expect(
        app.managedUsers,
        hasLength(before),
        reason: 'the demo branch must not skip the validation the real '
            'path does',
      );
    });
  });

  group('departments and organizations', () {
    test('a new department joins the list', () async {
      final app = await admin();
      final before = app.departments.length;

      final error = await app.createDepartment(code: 'CBA', name: 'Business');

      expect(error, isNull);
      expect(app.departments, hasLength(before + 1));
      expect(app.departments.last.code, 'CBA');
    });

    test('a new organization joins its department', () async {
      final app = await admin();
      final before = app.organizationsIn('demo-cite').length;

      final error = await app.createOrganization(
        code: 'ACM',
        name: 'Association for Computing Machinery',
        departmentId: 'demo-cite',
      );

      expect(error, isNull);
      expect(app.organizationsIn('demo-cite'), hasLength(before + 1));
    });
  });

  // Two things the phone showed that the state tests could not. Neither
  // computed anything wrongly; both read wrongly.
  group('how the admin screen reads', () {
    test('an invited account is not coloured as a finished one', () async {
      final app = await admin();
      final invited = app.managedUsers.firstWhere((u) => u.mustChangePassword);

      expect(invited.statusLabel, 'Awaiting password setup');
      expect(
        invited.isUsable,
        isTrue,
        reason: 'it is active and unsuspended, which is exactly why the '
            'badge was green — the screen must not key its colour off '
            'isUsable alone',
      );
    });

    test('an audit entry names someone the accounts list holds', () async {
      final app = await admin();
      final entry = app.auditLog.firstWhere((e) => e.userId != null);

      final named = app.managedUsers.where((u) => u.id == entry.userId);

      expect(
        named,
        isNotEmpty,
        reason: 'the demo log must point at accounts that exist, or the '
            'screen falls back to printing a database id',
      );
    });
  });
}
