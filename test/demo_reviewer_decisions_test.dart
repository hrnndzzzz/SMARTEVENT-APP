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

  group('the review history the demo can account for', () {
    Future<List<ApprovalRecord>> historyOf(AppState app, EventItem event) async
        => (await app.loadApprovals(event)).records!;

    test('a proposal awaiting the Moderator shows that step as open', () async {
      final app = AppState()..enterDemo(role: UserRole.adviser);

      final history = await historyOf(app, pending(app));

      expect(history, hasLength(1));
      expect(history.single.stepOrder, 1);
      expect(history.single.decision, 'pending');
      expect(history.single.decidedAt, isNull, reason: 'it has not been');
    });

    test('an approved event accounts for every stage', () async {
      final app = AppState()..enterDemo(role: UserRole.adviser);
      final event = app.events.firstWhere(
        (e) => e.status == EventApprovalStatus.approved,
      );

      final history = await historyOf(app, event);

      expect(history.map((r) => r.decision), everyElement('approved'));
      expect(history.map((r) => r.stepOrder), [1, 2, 3]);
    });

    test('a rejection names the step it stopped at and goes no further',
        () async {
      final app = AppState()..enterDemo(role: UserRole.adviser);
      final event = pending(app);
      await app.adviserDecision(
        event,
        approved: false,
        note: 'The budget does not add up.',
        expectedVersion: null, // no version: a rejection, not a return
      );

      final history = await historyOf(app, event);

      expect(history, hasLength(1));
      expect(history.single.decision, 'rejected');
      expect(history.single.remarks, contains('budget'));
    });

    test('a return reads as returned, not rejected', () async {
      final app = AppState()..enterDemo(role: UserRole.adviser);
      final event = pending(app);
      await app.adviserDecision(
        event,
        approved: false,
        note: 'Part 3 needs the venue permit.',
        expectedVersion: await app.proposalVersionFor(event),
      );

      final history = await historyOf(app, event);

      expect(history.single.decision, 'returned');
      expect(history.single.remarks, contains('venue permit'));
    });

    // Caught on a phone: the seeded rejection is the SDS Office's, and
    // matching the reviewer against "Adviser" and "Admin" alone left the
    // card reading "No review decisions recorded yet." under a badge that
    // said "Rejected by the SDS Office" — the contradiction this set out
    // to remove, in the one case most likely to be on screen.
    test('a rejection by the SDS Office stops at the stage after the admin',
        () async {
      final app = AppState()..enterDemo(role: UserRole.treasurer);
      final event = app.events.firstWhere(
        (e) => e.status == EventApprovalStatus.rejected,
      );
      expect(event.rejectedBy, isNot(anyOf('Adviser', 'Admin')),
          reason: 'the case the name-matching missed');

      final history = await historyOf(app, event);

      expect(history.map((r) => r.decision), ['approved', 'approved', 'rejected']);
      expect(history.last.stepOrder, 3);
      expect(history.last.remarks, contains('morning classes'),
          reason: "the office's reason is on the proposal, and is read from it");
    });

    test('a draft nobody has reviewed still records nothing', () async {
      final app = AppState()..enterDemo(role: UserRole.adviser);
      final draft = app.events.firstWhere(
        (e) =>
            e.status == EventApprovalStatus.draft &&
            (e.adviserApprovalNote ?? '').isEmpty,
      );

      expect(
        await historyOf(app, draft),
        isEmpty,
        reason: 'inventing a step for an unsubmitted draft would be a lie',
      );
    });
  });
}
