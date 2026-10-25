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
      expect(officer.mayProposeEvents, isFalse);
      expect(officer.mayRecordFinance, isFalse);
    });

    test('an administrator keeps recording, which develop allows', () {
      // The live backend lets an admin record; only the unmerged
      // hierarchy branch narrows it. Denying here would break the app
      // against the server it actually talks to.
      final admin = signedInAs(UserRole.admin);

      expect(admin.mayRecordFinance, isTrue);
    });
  });

  group('when the server answers', () {
    test('an Officer who is President may propose', () {
      final app = signedInAs(UserRole.officer);
      expect(app.mayProposeEvents, isFalse, reason: 'the role says no');

      app.permissionsForTest = const AccountPermissions(
        role: 'officer',
        position: 'President',
        canProposeEvents: true,
        canRecordFinance: false,
      );

      expect(
        app.mayProposeEvents,
        isTrue,
        reason: 'no role name can express this, which is the whole point',
      );
    });

    test('an administrator is refused recording when the server says so', () {
      final app = signedInAs(UserRole.admin);
      expect(app.mayRecordFinance, isTrue, reason: 'the role says yes');

      app.permissionsForTest = const AccountPermissions(
        role: 'admin',
        canRecordFinance: false,
      );

      expect(
        app.mayRecordFinance,
        isFalse,
        reason: 'otherwise the app offers a button that answers 403',
      );
    });

    test('a reply carrying neither flag changes nothing', () {
      final app = signedInAs(UserRole.admin);

      app.permissionsForTest = const AccountPermissions(role: 'admin');

      expect(app.mayRecordFinance, isTrue);
      expect(app.mayProposeEvents, isTrue);
    });
  });
}
