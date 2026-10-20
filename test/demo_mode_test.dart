import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/compliance_service.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/user_role.dart';

/// Exploring has to fill the app, not fake a login against a server it
/// cannot reach. These check the difference.
void main() {
  test('entering the demo fills every collection', () {
    final app = AppState()..enterDemo();

    expect(app.isDemoMode, isTrue);
    expect(app.currentRole, UserRole.treasurer);
    expect(app.events, isNotEmpty);
    expect(app.expenses, isNotEmpty);
    expect(app.categories, isNotEmpty);
    expect(app.notices, isNotEmpty);
    expect(app.unreadNoticeCount, greaterThan(0));
  });

  test('every event state is represented, so no filter is empty', () {
    final app = AppState()..enterDemo();
    final states = app.events.map((e) => e.status).toSet();

    for (final wanted in [
      EventApprovalStatus.draft,
      EventApprovalStatus.pendingAdviser,
      EventApprovalStatus.approved,
      EventApprovalStatus.rejected,
      EventApprovalStatus.completed,
    ]) {
      expect(states, contains(wanted), reason: '$wanted has no demo event');
    }
  });

  test('no module is left looking like it is still loading', () {
    final app = AppState()..enterDemo();
    expect(app.eventsLoad.status, LoadStatus.ready);
    expect(app.expensesLoad.status, LoadStatus.ready);
  });

  test('a role can be chosen', () {
    final app = AppState()..enterDemo(role: UserRole.sdsStaff);
    expect(app.currentRole, UserRole.sdsStaff);
    expect(app.currentAccount?.name, 'Demo SDS Staff');
  });

  test('nothing reaches for a server while exploring', () async {
    // The event detail screen calls these two straight out rather than
    // through the load wrapper, so they each need their own guard. A red
    // "could not reach the backend" on a demo is the whole point missed.
    final app = AppState()..enterDemo();

    final approvals = await app.loadApprovals(app.events.first);
    expect(approvals.error, isNull);
    expect(approvals.records, isEmpty);

    await expectLater(
      app.eventReadiness('demo-ev-1'),
      throwsA(isA<FeatureUnavailable>()),
      reason: 'the notice stays silent on this, rather than going red',
    );
  });

  test('signing out leaves the demo', () async {
    final app = AppState()..enterDemo();
    await app.signOut();
    expect(app.isDemoMode, isFalse);
    expect(app.currentRole, isNull);
  });
}
