import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/widgets/event_picker_items.dart';

/// Money and stock are recorded against events that are approved, waiting
/// or finished, each marked with a dot — never against drafts or returns.
void main() {
  final today = DateTime(2026, 11, 8);

  EventItem event(String id, EventApprovalStatus status, {DateTime? on}) =>
      EventItem(
        remoteId: id,
        title: id,
        org: 'Org',
        date: '',
        on: on,
        budget: '0',
        status: status,
      );

  test('green, then yellow, then blue; drafts and returns are left out', () {
    final items = eventPickerItems([
      event('draft', EventApprovalStatus.draft),
      event('past', EventApprovalStatus.approved, on: DateTime(2026, 11, 1)),
      event('waiting', EventApprovalStatus.pendingAdmin),
      event('returned', EventApprovalStatus.rejected),
      event('ahead', EventApprovalStatus.approved, on: DateTime(2026, 11, 20)),
      event('done', EventApprovalStatus.completed),
      event('today', EventApprovalStatus.approved, on: today),
    ], today: today);

    expect(items.map((i) => i.value), [
      'ahead',
      'today',
      'waiting',
      'past',
      'done',
    ]);
  });

  test('the chosen event stays listed, so the dropdown keeps its value', () {
    final items = eventPickerItems([
      event('draft', EventApprovalStatus.draft),
    ], keep: 'draft', today: today);

    expect(items.single.value, 'draft');
  });

  test('each dot names its meaning, not only its colour', () {
    final approved = eventPickerDot(
      event('a', EventApprovalStatus.approved),
      today: today,
    );
    final waiting = eventPickerDot(
      event('w', EventApprovalStatus.pendingInstitutional),
      today: today,
    );
    final past = eventPickerDot(
      event('p', EventApprovalStatus.approved, on: DateTime(2026, 1, 1)),
      today: today,
    );

    expect((approved!.tone, approved.label), (BrutTone.mint, 'Approved'));
    expect((waiting!.tone, waiting.label), (
      BrutTone.sun,
      'Waiting for approval',
    ));
    expect((past!.tone, past.label), (BrutTone.brand, 'Past'));
    expect(
      eventPickerDot(event('d', EventApprovalStatus.draft), today: today),
      isNull,
    );
  });
}
