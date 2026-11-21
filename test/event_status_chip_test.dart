import 'package:flutter_test/flutter_test.dart';

import 'package:smartevent/state/app_state.dart';

/// A status chip that fits the row it sits in.
///
/// Reported from a handset: the events list showed "Pending Adviser…",
/// "Rejected by the …" and "With the signat…". It is the only thing on
/// the row saying where the activity has got to, and two different
/// statuses can clip to the same text.
void main() {
  EventItem withStatus(EventApprovalStatus status, {String? by}) => EventItem(
    title: 'HACK THE FUTURE',
    org: 'ACPES',
    date: '8 Jan 2027',
    budget: '\u20b12,000.00',
    status: status,
    rejectedBy: by,
  );

  test('every status fits a badge', () {
    for (final status in EventApprovalStatus.values) {
      final short = withStatus(status).statusShort;
      expect(short, isNotEmpty);
      expect(
        short.length,
        lessThanOrEqualTo(16),
        reason: '"$short" is long enough to clip again',
      );
    }
  });

  test('the ones that were clipping are now whole words', () {
    expect(
      withStatus(EventApprovalStatus.pendingAdviser).statusShort,
      'With adviser',
    );
    expect(
      withStatus(EventApprovalStatus.pendingInstitutional).statusShort,
      'With signatories',
    );
  });

  test('two statuses never read the same', () {
    final seen = <String>{};
    for (final status in EventApprovalStatus.values) {
      expect(
        seen.add(withStatus(status).statusShort),
        isTrue,
        reason: 'two statuses share a chip label',
      );
    }
  });

  test('the long label still names who rejected it', () {
    // The chip drops the name; the detail screen, which has the room,
    // keeps it.
    final event = withStatus(EventApprovalStatus.rejected, by: 'the Dean');
    expect(event.statusShort, 'Rejected');
    expect(event.statusLabel, 'Rejected by the Dean');
  });
}
