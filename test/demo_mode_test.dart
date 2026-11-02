import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/compliance_service.dart';
import 'package:smartevent/api/api_client.dart';
import 'package:smartevent/api/models/academic.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/user_role.dart';

/// Exploring has to fill the app, not fake a login against a server it
/// cannot reach. These check the difference.
void main() {
  test('the client refuses every verb while exploring', () async {
    // The net under the specific handlers above. Dozens of calls exist
    // and guarding each one is how a leak survives; this refuses at the
    // one place they all pass through.
    final client = ApiClient()..demoMode = true;

    for (final call in <Future<Object?> Function()>[
      () => client.get('/events'),
      () => client.post('/events', body: const {}),
      () => client.patch('/events/1', body: const {}),
      () => client.put('/events/1', body: const {}),
      () async {
        await client.delete('/events/1');
        return null;
      },
    ]) {
      // Future.sync, because the guard throws before it returns a
      // future at all — which is what fail-fast looks like, and is
      // still caught by a caller's try/await.
      await expectLater(Future.sync(call), throwsA(isA<DemoUnavailable>()));
    }
  });

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
      // With the SDS Office, which is the one the demo's SDS role reviews.
      EventApprovalStatus.pendingInstitutional,
      EventApprovalStatus.approved,
      EventApprovalStatus.rejected,
      EventApprovalStatus.completed,
    ]) {
      expect(states, contains(wanted), reason: '$wanted has no demo event');
    }
  });

  // A rejection is final and the SDS Office's alone. The demo's used to name
  // a person and carry a notice about being returned for revision.
  test('the rejected event is the SDS Office\'s, in its status and notice', () {
    final app = AppState()..enterDemo();
    final event = app.events.firstWhere(
      (e) => e.status == EventApprovalStatus.rejected,
    );
    final notice = app.notices.firstWhere(
      (n) => n.payload['event_id'] == event.remoteId,
    );

    expect(event.statusLabel, 'Rejected by the SDS Office');
    expect(notice.title.toLowerCase(), contains('rejected'));
    expect(notice.body, contains('SDS Office'));
    expect(
      '${notice.title} ${notice.body}'.toLowerCase(),
      isNot(contains('return')),
    );
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

  test('creating an event works without a server', () async {
    final app = AppState()..enterDemo();
    final before = app.events.length;

    final error = await app.addEvent(
      title: 'Demo seminar',
      estimatedCost: 1500,
      eventDate: DateTime(2026, 11, 20),
      schoolYear: '2026-2027',
      semester: Semester.first,
      eventScope: EventScope.organizational,
    );

    expect(error, isNull, reason: 'a demo that cannot create is not a demo');
    expect(app.events.length, before + 1);
    expect(app.events.first.title, 'Demo seminar');
    expect(app.events.first.remoteId, isNotNull);
  });

  test('a notification can be marked read without a server', () async {
    final app = AppState()..enterDemo();
    final before = app.unreadNoticeCount;

    final error = await app.markNoticeRead(app.notices.first);

    expect(error, isNull);
    expect(app.unreadNoticeCount, before - 1);
  });

  test('signing out leaves the demo', () async {
    final app = AppState()..enterDemo();
    await app.signOut();
    expect(app.isDemoMode, isFalse);
    expect(app.currentRole, isNull);
  });
}
