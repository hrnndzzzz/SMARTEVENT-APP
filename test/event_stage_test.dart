import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/app_state.dart';
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
    expect(
      EventStage.of(EventApprovalStatus.pendingAdmin),
      EventStage.withSds,
    );
    expect(
      EventStage.of(EventApprovalStatus.pendingInstitutional),
      EventStage.withSignatories,
    );
  });

  test('and no two of them read the same', () {
    final labels = {
      EventStage.withModerator.label,
      EventStage.withSds.label,
      EventStage.withSignatories.label,
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
      lessThan(EventStage.withSds.reached),
    );
    expect(
      EventStage.withSds.reached,
      lessThan(EventStage.withSignatories.reached),
    );
    expect(
      EventStage.withSignatories.reached,
      lessThan(EventStage.approved.reached),
    );
  });

  test('nothing fills past the end of the bar', () {
    for (final stage in EventStage.values) {
      expect(stage.reached, lessThanOrEqualTo(EventStage.segments),
          reason: stage.name);
      expect(stage.reached, greaterThanOrEqualTo(0), reason: stage.name);
    }
  });

  test('waiting is amber, back with you is red, through is green', () {
    expect(EventStage.withModerator.tone, EventStage.withSds.tone);
    expect(EventStage.returned.tone, isNot(EventStage.withSds.tone));
    expect(EventStage.approved.tone, EventStage.completed.tone);
  });

  test('each desk says who is actually holding it up', () {
    expect(EventStage.withModerator.note, contains('moderator'));
    expect(EventStage.withSds.note, contains('SDS'));
    expect(EventStage.withSignatories.note, contains('signatures'));
  });
}
