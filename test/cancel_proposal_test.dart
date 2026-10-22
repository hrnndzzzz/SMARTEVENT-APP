import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/user_role.dart';

/// Taking your own proposal back while it is still anyone's to decide on.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  EventItem pendingEvent(AppState app) =>
      app.events.firstWhere((e) => e.status.isPending);

  test('a pending proposal goes back to a draft', () async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final event = pendingEvent(app);

    expect(await app.cancelProposal(event), isNull);
    expect(event.status, EventApprovalStatus.draft);
  });

  test('and nothing written on it is lost', () async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final event = pendingEvent(app);
    final title = event.title;
    final budget = event.budget;

    await app.cancelProposal(event);

    expect(event.title, title);
    expect(event.budget, budget);
  });

  test('a decided proposal cannot be taken back', () async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);

    // One event, set to each decided state in turn: looking it up again
    // each time would fail, because the first pass stops it being
    // pending.
    final event = pendingEvent(app);

    for (final status in [
      EventApprovalStatus.approved,
      EventApprovalStatus.rejected,
      EventApprovalStatus.completed,
      EventApprovalStatus.draft,
    ]) {
      event.status = status;
      final problem = await app.cancelProposal(event);

      expect(problem, isNotNull, reason: status.name);
      expect(event.status, status, reason: 'left alone');
    }
  });

  test('the decision that was made is not erased by it', () async {
    final app = AppState()..enterDemo(role: UserRole.treasurer);
    final event = pendingEvent(app)
      ..status = EventApprovalStatus.rejected
      ..rejectedBy = 'The SDS Office';

    await app.cancelProposal(event);

    expect(event.rejectedBy, 'The SDS Office');
  });
}
