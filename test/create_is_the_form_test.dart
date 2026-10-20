import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/state/sap_form.dart';

/// Filling the form is how an event gets made. The record is a
/// consequence of Part 1, not a separate thing asked for beforehand, so
/// the form has to work before any event exists.
void main() {
  test('a form can be written in before it has an event', () async {
    final form = SapForm();
    expect(form.hasEvent, isFalse);
    expect(form.eventId, isNull);

    await form.load();
    form.updateDetails(
      (d) => d.copyWith(
        title: 'Hack the Future',
        activityDate: DateTime(2026, 10, 28),
        totalBudget: '2500.00',
      ),
    );

    // Nothing is sent, and nothing is lost.
    expect(await form.saveDetails(), isTrue);
    expect(form.details.title, 'Hack the Future');
  });

  test('what was written before the event survives binding to one', () async {
    final form = SapForm();
    await form.load();
    form.updateDetails((d) => d.copyWith(title: 'Written first'));
    form.setProgramFlow(const [
      SapProgramFlowItem(
        start: SapTime(8, 0),
        end: SapTime(9, 0),
        activity: 'Opening',
      ),
    ]);

    await form.bindEvent('event-made-after');

    expect(form.eventId, 'event-made-after');
    expect(form.hasEvent, isTrue);
    expect(form.details.title, 'Written first');
    expect(form.programFlow, hasLength(1));
  });

  test('binding twice does not reattach it elsewhere', () async {
    final form = SapForm(eventId: 'first');
    await form.bindEvent('second');
    expect(form.eventId, 'first');
  });
}
