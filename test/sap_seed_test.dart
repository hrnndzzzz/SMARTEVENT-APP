import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/state/sap_form.dart';

/// Creating an event and filling its form ask for the same half-dozen
/// things. Typing them twice is how the second one goes unfilled.
void main() {
  SapDetails seed() => SapDetails(
    title: 'Hack the Future',
    organizationName: 'ACPES',
    schoolYear: '2026-2027',
    scope: 'organizational',
    activityDate: DateTime(2026, 10, 28),
    proposalDate: DateTime(2026, 10, 20),
    totalBudget: '2500.00',
    rationale: 'A seminar on cybersecurity.',
  );

  test('an empty form opens filled from what the event was created with',
      () async {
    final form = SapForm(eventId: 'e1', seed: seed());
    await form.load();

    expect(form.details.title, 'Hack the Future');
    expect(form.details.organizationName, 'ACPES');
    expect(form.details.schoolYear, '2026-2027');
    expect(form.details.scope, 'organizational');
    expect(form.details.activityDate, DateTime(2026, 10, 28));
    expect(form.details.totalBudget, '2500.00');
    expect(form.details.rationale, 'A seminar on cybersecurity.');
  });

  test('a form somebody has already written in is left alone', () async {
    final form = SapForm(eventId: 'e1', seed: seed());
    form.updateDetails((d) => d.copyWith(title: 'What they actually typed'));
    await form.load();

    expect(form.details.title, 'What they actually typed');
    // And the seed does not sneak the rest in around it.
    expect(form.details.schoolYear, isNull);
  });

  test('no seed changes nothing', () async {
    final form = SapForm(eventId: 'e1');
    await form.load();
    expect(form.details.title, isNull);
  });
}
