import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/app_state.dart';

/// The review half of the workflow, in the demo.
///
/// The Moderator's and Dean's decisions went straight to the server, and
/// the client refuses every request in demo mode — so the demo showed
/// the buttons and refused the press with "nothing is sent to a server".
/// The review is what the moderator's feedback is about, so it has to be
/// demonstrable without a backend.
void main() {
  EventItem pending(AppState app) =>
      app.events.firstWhere((e) => e.status == EventApprovalStatus.pendingAdviser);

  test('the Moderator approving sends it to the Dean', () async {
    final app = AppState()..enterDemo(role: UserRole.adviser);
    final event = pending(app);

    final outcome = await app.adviserDecision(event, approved: true);

    expect(outcome.error, isNull, reason: 'the demo must not refuse this');
    expect(event.status, EventApprovalStatus.pendingAdmin);
  });

  test('a return for revision goes back as a draft, rejected by nobody', () async {
    final app = AppState()..enterDemo(role: UserRole.adviser);
    final event = pending(app);

    final outcome = await app.adviserDecision(
      event,
      approved: false,
      note: 'Budget needs a quantity on the certificates line.',
      expectedVersion: 3,
    );

    expect(outcome.error, isNull);
    expect(event.status, EventApprovalStatus.draft);
    expect(
      event.rejectedBy,
      isNull,
      reason: 'a return is not a rejection, and must not read as one',
    );
    expect(event.adviserApprovalNote, contains('certificates'));
  });

  test('a rejection without a version is a rejection, and says who', () async {
    final app = AppState()..enterDemo(role: UserRole.adviser);
    final event = pending(app);

    await app.adviserDecision(event, approved: false, note: 'Not this term.');

    expect(event.status, EventApprovalStatus.rejected);
    expect(event.rejectedBy, 'Adviser');
  });

  test('the Dean approving finishes it', () async {
    final app = AppState()..enterDemo(role: UserRole.admin);
    final event = pending(app)..status = EventApprovalStatus.pendingAdmin;

    final outcome = await app.adminDecision(event, approved: true);

    expect(outcome.error, isNull);
    expect(event.status, EventApprovalStatus.approved);
  });

  test('and the Dean returning names the Dean', () async {
    final app = AppState()..enterDemo(role: UserRole.admin);
    final event = pending(app)..status = EventApprovalStatus.pendingAdmin;

    await app.adminDecision(event, approved: false, note: 'Over allocation.');

    expect(event.status, EventApprovalStatus.rejected);
    expect(event.rejectedBy, 'Admin');
    expect(event.adminApprovalNote, 'Over allocation.');
  });

  // The screen reads `isProposal` off this, and so does the demo's own
  // decision: without a version every return came out as a rejection,
  // the badge reading "Rejected by Adviser" under a message that said it
  // had been returned. In the demo the version cannot be fetched, so a
  // seeded proposal reports one of its own.
  test('a seeded proposal reports a version in the demo', () async {
    final app = AppState()..enterDemo(role: UserRole.adviser);

    expect(await app.proposalVersionFor(pending(app)), isNotNull);
  });

  test('and the Moderator returning it reads as returned, not rejected',
      () async {
    final app = AppState()..enterDemo(role: UserRole.adviser);
    final event = pending(app);

    // The version the screen would have handed the decision.
    final version = await app.proposalVersionFor(event);
    await app.adviserDecision(
      event,
      approved: false,
      note: 'Part 3 is missing the venue permit.',
      expectedVersion: version,
    );

    expect(event.status, EventApprovalStatus.draft);
    expect(event.rejectedBy, isNull);
  });
}
