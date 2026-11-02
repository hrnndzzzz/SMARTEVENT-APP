import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/widgets/event_progress_bar.dart';

/// Which desk has it.
///
/// The three pending statuses used to collapse into one "With the
/// reviewers", on the argument that the proposer can do nothing
/// differently whichever desk holds it. True, but they can see that it
/// moved — and a proposal sitting with the moderator for a week is not
/// the same thing as one that reached the SDS Office yesterday.
void main() {
  test('each waiting status names its own desk', () {
    expect(
      EventStage.of(EventApprovalStatus.pendingAdviser),
      EventStage.withModerator,
    );
    // The Dean comes before the SDS Office, not after it: this used to
    // say the SDS Office had a proposal the Dean was still deciding.
    expect(
      EventStage.of(EventApprovalStatus.pendingAdmin),
      EventStage.withDean,
    );
    expect(
      EventStage.of(EventApprovalStatus.pendingInstitutional),
      EventStage.withSds,
    );
  });

  test('and no two of them read the same', () {
    final labels = {
      EventStage.withModerator.label,
      EventStage.withDean.label,
      EventStage.withSds.label,
    };
    expect(labels, hasLength(3));
  });

  test('every status still maps somewhere', () {
    for (final status in EventApprovalStatus.values) {
      expect(EventStage.of(status).label.trim(), isNotEmpty,
          reason: status.name);
    }
  });

  test('the bar fills further as it moves along', () {
    expect(
      EventStage.withModerator.reached,
      lessThan(EventStage.withDean.reached),
    );
    expect(EventStage.withDean.reached, lessThan(EventStage.withSds.reached));
    expect(EventStage.withSds.reached, lessThan(EventStage.approved.reached));
  });

  test('nothing fills past the end of the bar', () {
    for (final stage in EventStage.values) {
      expect(stage.reached, lessThanOrEqualTo(EventStage.segments),
          reason: stage.name);
      expect(stage.reached, greaterThanOrEqualTo(0), reason: stage.name);
    }
  });

  test('waiting is amber, rejected is red, through is green', () {
    expect(EventStage.withModerator.tone, EventStage.withDean.tone);
    expect(EventStage.withDean.tone, EventStage.withSds.tone);
    expect(EventStage.rejected.tone, isNot(EventStage.withSds.tone));
    expect(EventStage.approved.tone, EventStage.completed.tone);
  });

  test('each desk says who is actually holding it up', () {
    expect(EventStage.withModerator.note, contains('moderator'));
    expect(EventStage.withDean.note, contains('Dean'));
    expect(EventStage.withSds.label, contains('SDS Office'));
  });

  // The SDS Office signing does not move the event: it stays at
  // pending_institutional_review while the paper goes round for the nine
  // signatures, until the final scan. "Waiting on the SDS Office" stopped
  // being true halfway through that stage.
  test('the SDS Office stage holds while the paper goes round, too', () {
    final note = EventStage.withSds.note;

    expect(note, contains('signing'));
    expect(note, contains('nine signatures'));
    expect(note, isNot(contains('Waiting')));
  });

  // Set on one line and cut off with an ellipsis, so a longer one is lost on
  // a narrow phone: a 360px card holds about 41 characters of it.
  test('every note fits the one line it is set on', () {
    for (final stage in EventStage.values) {
      expect(stage.note.length, lessThanOrEqualTo(40), reason: stage.name);
    }
  });

  // The SDS Office's rejection is its final word. The bar used to call
  // that "Back with you / Needs a change from you", which is a return.
  test('a rejection reads as final, with nothing asked of anyone', () {
    final stage = EventStage.of(EventApprovalStatus.rejected);

    expect(stage, EventStage.rejected);
    expect(stage.label, 'Rejected');
    expect(stage.tone, BrutTone.coral);
    expect(stage.note.toLowerCase(), isNot(contains('change')));
  });
}
