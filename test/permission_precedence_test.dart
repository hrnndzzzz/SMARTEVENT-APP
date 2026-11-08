import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/account_permissions.dart';
import 'package:smartevent/state/app_state.dart';

/// Which capability wins. The server's answer where it gives one, the
/// role's built-in default where it does not — and absence must never
/// read as a denial, or the app locks itself against the backend that is
/// actually deployed, which does not send these flags at all.
void main() {
  AppState signedInAs(UserRole role) => AppState()..devQuickLogin(role);

  group('with no answer from the server', () {
    test('the role still decides, exactly as it did before', () {
      final treasurer = signedInAs(UserRole.treasurer);
      expect(treasurer.permissions, isNull);
      expect(treasurer.mayProposeEvents, isTrue);
      expect(treasurer.mayRecordFinance, isTrue);

      final officer = signedInAs(UserRole.officer);
      expect(officer.mayProposeEvents, isTrue);
      expect(officer.mayRecordFinance, isTrue);
    });

    test('an administrator reviews money rather than recording it', () {
      // The backend's FINANCIAL_ROLES are the officer and the Treasurer;
      // offering an admin the button only led to a 403.
      final admin = signedInAs(UserRole.admin);

      expect(admin.mayRecordFinance, isFalse);
    });
  });

  group('when the server answers', () {
    test('an Officer the server refuses may not propose', () {
      final app = signedInAs(UserRole.officer);
      expect(app.mayProposeEvents, isTrue, reason: 'the role says yes');

      app.permissionsForTest = const AccountPermissions(
        role: 'officer',
        canProposeEvents: false,
        canRecordFinance: false,
      );

      expect(
        app.mayProposeEvents,
        isFalse,
        reason: 'the server decides, so a policy change needs no release',
      );
    });

    test('an officer is refused recording when the server says so', () {
      final app = signedInAs(UserRole.officer);
      expect(app.mayRecordFinance, isTrue, reason: 'the role says yes');

      app.permissionsForTest = const AccountPermissions(
        role: 'officer',
        canRecordFinance: false,
      );

      expect(
        app.mayRecordFinance,
        isFalse,
        reason: 'otherwise the app offers a button that answers 403',
      );
    });

    test('a reply carrying neither flag changes nothing', () {
      final app = signedInAs(UserRole.treasurer);

      app.permissionsForTest = const AccountPermissions(role: 'treasurer');

      expect(app.mayRecordFinance, isTrue);
      expect(app.mayProposeEvents, isTrue);
    });
  });
}
