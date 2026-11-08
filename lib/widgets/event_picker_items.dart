import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// The dot an event gets in a picker, or null when it is not offered.
///
/// Green is approved, yellow is still waiting on a decision, blue is over:
/// completed, or approved with its day already gone. Drafts and returned
/// proposals are left out — money and stock are not recorded against them.
({BrutTone tone, String label})? eventPickerDot(
  EventItem event, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final on = event.on;
  final past =
      on != null &&
      DateTime(on.year, on.month, on.day).isBefore(
        DateTime(now.year, now.month, now.day),
      );
  return switch (event.status) {
    EventApprovalStatus.completed => (tone: BrutTone.brand, label: 'Past'),
    EventApprovalStatus.approved when past => (
      tone: BrutTone.brand,
      label: 'Past',
    ),
    EventApprovalStatus.approved => (tone: BrutTone.mint, label: 'Approved'),
    final status when status.isPending => (
      tone: BrutTone.sun,
      label: 'Waiting for approval',
    ),
    _ => null,
  };
}

/// Dropdown items for choosing an event to record money or stock against.
///
/// Green first, then yellow, then blue. [keep] is the value already chosen:
/// it stays listed even when its event would not be offered, because a
/// dropdown whose value is missing from its items throws.
List<DropdownMenuItem<String>> eventPickerItems(
  List<EventItem> events, {
  String? keep,
  DateTime? today,
}) {
  final groups = {BrutTone.mint: <DropdownMenuItem<String>>[],
      BrutTone.sun: <DropdownMenuItem<String>>[],
      BrutTone.brand: <DropdownMenuItem<String>>[]};
  final kept = <DropdownMenuItem<String>>[];
  for (final event in events) {
    final id = event.remoteId;
    if (id == null) continue;
    final dot = eventPickerDot(event, today: today);
    final item = DropdownMenuItem(
      value: id,
      child: _EventRow(title: event.title, dot: dot),
    );
    if (dot != null) {
      groups[dot.tone]!.add(item);
    } else if (id == keep) {
      kept.add(item);
    }
  }
  return [for (final group in groups.values) ...group, ...kept];
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.title, required this.dot});

  final String title;
  final ({BrutTone tone, String label})? dot;

  @override
  Widget build(BuildContext context) {
    final dot = this.dot;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot != null) ...[
          // Said aloud too, so the meaning never rests on colour alone.
          Semantics(
            label: dot.label,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dot.tone.fill(context),
                shape: BoxShape.circle,
                border: Border.all(color: context.palette.ink, width: 0.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
