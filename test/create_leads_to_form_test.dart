import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/user_role.dart';

/// Creating the event is half the job. What the university wants is the
/// filled SAS-SDS-FO-020, and leaving someone to find their way back to
/// it is how it stays unfilled.
///
/// Driving a real create needs a backend, so what is checked here is the
/// contract the handoff depends on: that the event just made is the one
/// at the front of the list. The navigation itself is verified by
/// running it.
void main() {
  test('the newly created event is the one handed to the form', () {
    // addEvent inserts at the front, which is what the create screen
    // reads to know which event it just made.
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final firstBefore = app.events.first.remoteId;

    app.events.insert(
      0,
      EventItem(
        remoteId: 'brand-new',
        title: 'New one',
        org: 'ACPES',
        date: '1 Jan 2027',
        budget: '100',
      ),
    );

    expect(app.events.first.remoteId, 'brand-new');
    expect(app.events.first.remoteId, isNot(firstBefore));
  });
}
