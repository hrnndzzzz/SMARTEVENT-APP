import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/demo_data.dart';

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

  group('the movement ledger in the demo', () {
    // A movement is the only way stock changes, so the ledger has to
    // account for the figure on the card above it. A ledger that
    // disagreed would be worse than the error it replaced.
    test('every item\'s movements sum to the stock it shows', () {
      for (final item in DemoData.catalog()) {
        final moves = DemoData.movementsFor(item.id);
        expect(
          moves.fold<int>(0, (sum, m) => sum + m.changeQty),
          item.quantity,
          reason: '${item.itemName} does not add up to its own quantity',
        );
      }
    });

    test('no movement is of nothing', () {
      for (final item in DemoData.catalog()) {
        for (final move in DemoData.movementsFor(item.id)) {
          expect(move.changeQty, isNot(0), reason: item.itemName);
        }
      }
    });

    test('the ledger is answered rather than refused', () async {
      final app = AppState()..enterDemo(role: UserRole.admin);
      final item = DemoData.catalog().first;

      final outcome = await app.loadMovements(item);

      expect(outcome.error, isNull, reason: 'the demo must not refuse it');
      expect(outcome.movements, isNotEmpty);
    });

    test('narrowing to an event leaves only that event\'s movements',
        () async {
      final app = AppState()..enterDemo(role: UserRole.admin);
      final item = DemoData.catalog()
          .firstWhere((i) => i.id == 'demo-inv-1');

      final outcome = await app.loadMovements(item, eventId: 'demo-ev-2');

      expect(outcome.movements, isNotEmpty);
      expect(
        outcome.movements!.every((m) => m.eventId == 'demo-ev-2'),
        isTrue,
      );
    });
  });

  group('recording a movement in the demo', () {
    RemoteInventoryItem tables(AppState app) =>
        app.catalog.firstWhere((i) => i.id == 'demo-inv-1');

    test('the stock moves and the ledger says why', () async {
      final app = AppState()..enterDemo(role: UserRole.treasurer);
      final before = tables(app).quantity;

      final error = await app.recordInventoryMovement(
        tables(app),
        type: InventoryMovementType.issue,
        eventId: 'demo-ev-2',
        count: '2',
        reason: 'Taken for the opening ceremony',
      );

      expect(error, isNull, reason: 'the demo must not refuse this');
      expect(tables(app).quantity, before - 2);

      final ledger = (await app.loadMovements(tables(app))).movements!;
      expect(ledger.first.changeQty, -2);
      expect(ledger.first.reason, contains('opening ceremony'));
    });

    test('and the ledger still accounts for the stock afterwards',
        () async {
      final app = AppState()..enterDemo(role: UserRole.treasurer);
      await app.recordInventoryMovement(
        tables(app),
        type: InventoryMovementType.acquisition,
        eventId: 'demo-ev-2',
        count: '5',
        reason: 'Three more bought for registration',
      );

      final ledger = (await app.loadMovements(tables(app))).movements!;
      expect(
        ledger.fold<int>(0, (sum, m) => sum + m.changeQty),
        tables(app).quantity,
      );
    });

    // Filtering rebuilt the catalog from the seed, which put the stock
    // back to what it was the moment a chip was tapped.
    test('a filter does not undo it', () async {
      final app = AppState()..enterDemo(role: UserRole.treasurer);
      await app.recordInventoryMovement(
        tables(app),
        type: InventoryMovementType.issue,
        eventId: 'demo-ev-2',
        count: '4',
        reason: 'Lent to the College of Education',
      );
      final after = tables(app).quantity;

      await app.applyCatalogFilter(isDraft: false);
      await app.applyCatalogFilter();

      expect(tables(app).quantity, after);
    });

    test('it still refuses to take stock below zero', () async {
      final app = AppState()..enterDemo(role: UserRole.treasurer);

      final error = await app.recordInventoryMovement(
        tables(app),
        type: InventoryMovementType.issue,
        eventId: 'demo-ev-2',
        count: '999',
        reason: 'More than there are',
      );

      expect(error, contains('below zero'));
      expect(tables(app).quantity, 12, reason: 'nothing moved');
    });
  });

  group('the inventory filters in the demo', () {
    // These are the server's filters, so in the demo choosing one
    // highlighted the chip and left every item on screen — including
    // the ones it was meant to exclude.
    test('unconfirmed drafts narrows to the drafted item', () async {
      final app = AppState()..enterDemo(role: UserRole.admin);
      await app.applyCatalogFilter(isDraft: true);

      expect(app.catalog, isNotEmpty);
      expect(app.catalog.every((i) => i.isDraft), isTrue);
      expect(app.catalog.length, lessThan(DemoData.catalog().length));
    });

    test('needs event link narrows to items with no event', () async {
      final app = AppState()..enterDemo(role: UserRole.admin);
      await app.applyCatalogFilter(missingEventOnly: true);

      expect(app.catalog, isNotEmpty);
      expect(app.catalog.every((i) => i.eventId == null), isTrue);
    });

    test('clearing it brings the whole catalog back', () async {
      final app = AppState()..enterDemo(role: UserRole.admin);
      await app.applyCatalogFilter(isDraft: true);
      await app.applyCatalogFilter();

      expect(app.catalog.length, DemoData.catalog().length);
    });
  });

  // C7, the moderator's "it is not clear how an inventory item is
  // created". The answer is that a purchase writes it as a draft for an
  // administrator to confirm — and the badge, the filter and the notice
  // that say so could never appear, because every seeded item was
  // already confirmed.
  test('the demo holds an item a purchase drafted', () {
    final drafts = DemoData.catalog().where((i) => i.isDraft).toList();

    expect(drafts, hasLength(1), reason: 'one is enough to show the state');
    expect(drafts.single.eventId, isNotNull,
        reason: 'a purchase is made against an event');
  });
}
