import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/activity_service.dart';

/// The "Last change" line reads an audit action back as plain words.
void main() {
  test('a removal reads as a sentence, naming what is gone', () {
    final note = ActivityNote(
      action: 'inventory.deleted',
      actorName: 'Maria Santos',
      createdAt: DateTime(2026, 11, 8),
      subject: 'Batteries',
    );

    expect(note.sentence, 'Maria Santos removed Batteries');
  });

  test('actions map to verbs', () {
    expect(activityVerb('expense.recorded'), 'added');
    expect(activityVerb('sap_created'), 'added');
    expect(activityVerb('sap_details_updated'), 'edited');
    expect(activityVerb('inventory.archived'), 'removed');
    expect(activityVerb('sap_submitted'), 'submitted');
    expect(activityVerb('expense.approved'), 'approved');
    expect(
      activityVerb('inventory.movement_recorded'),
      'recorded a stock movement on',
    );
  });

  test('a missing subject leaves no dangling space', () {
    final note = ActivityNote(
      action: 'sap_submitted',
      actorName: 'Ana',
      createdAt: DateTime(2026, 11, 8),
      subject: null,
    );

    expect(note.sentence, 'Ana submitted');
  });
}
