import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// Where one of your events has got to, as a bar.
///
/// The question anyone with an event in the system actually has is "has
/// it moved?", and the answer is a position in a queue rather than a
/// number. So: four segments, filled up to where it is, coloured by
/// whether it is waiting on someone, waiting on you, or done.
///
/// Red means it is back with you and nothing happens until you act.
/// Amber means someone else has it. Green means it is through.
enum EventStage {
  drafting('Drafting', 0),
  waiting('With the reviewers', 1),
  returned('Back with you', 1),
  approved('Approved', 2),
  completed('Completed', 3);

  const EventStage(this.label, this.reached);

  final String label;

  /// How many of the four segments are filled. `index` is already an
  /// enum's own member, hence the name.
  final int reached;

  static const int segments = 4;

  BrutTone get tone => switch (this) {
    EventStage.drafting => BrutTone.neutral,
    EventStage.waiting => BrutTone.sun,
    EventStage.returned => BrutTone.coral,
    EventStage.approved => BrutTone.mint,
    EventStage.completed => BrutTone.mint,
  };

  /// What the person looking at it should do, if anything.
  String get note => switch (this) {
    EventStage.drafting => 'Not submitted yet',
    EventStage.waiting => 'Nothing for you to do',
    EventStage.returned => 'Needs a change from you',
    EventStage.approved => 'Ready to run',
    EventStage.completed => 'Closed out',
  };

  /// The three pending stages all read as "with the reviewers": which
  /// desk it is sitting on is the reviewers' business, and the proposer
  /// can do nothing differently for any of them.
  static EventStage of(EventApprovalStatus status) => switch (status) {
    EventApprovalStatus.draft => EventStage.drafting,
    EventApprovalStatus.pendingAdviser => EventStage.waiting,
    EventApprovalStatus.pendingAdmin => EventStage.waiting,
    EventApprovalStatus.pendingInstitutional => EventStage.waiting,
    EventApprovalStatus.rejected => EventStage.returned,
    EventApprovalStatus.approved => EventStage.approved,
    EventApprovalStatus.completed => EventStage.completed,
  };
}

/// The bar for one event.
class EventProgressBar extends StatelessWidget {
  const EventProgressBar({
    super.key,
    required this.title,
    required this.stage,
    this.onTap,
  });

  final String title;
  final EventStage stage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = stage.tone.fill(context);

    return BrutCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              BrutBadge(label: stage.label, tone: stage.tone),
            ],
          ),
          const SizedBox(height: 10),

          // Four segments, filled to where it is. A bar rather than a
          // percentage: there is no such thing as 40% approved.
          Row(
            children: [
              for (var i = 0; i < EventStage.segments; i++) ...[
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: i <= stage.reached ? fill : context.palette.line,
                      borderRadius: AppRadius.pill,
                      border: Border.fromBorderSide(context.side),
                    ),
                  ),
                ),
                if (i != EventStage.segments - 1) const SizedBox(width: 5),
              ],
            ],
          ),
          const SizedBox(height: 8),
          MonoLabel(stage.note),
        ],
      ),
    );
  }
}

/// Every event of yours that has not finished, newest first.
///
/// Nothing at all when there is nothing in flight: a dashboard that
/// always shows this block teaches people to stop reading it.
class EventProgressList extends StatelessWidget {
  const EventProgressList({super.key, required this.events, this.onOpen});

  final List<EventItem> events;
  final void Function(EventItem)? onOpen;

  @override
  Widget build(BuildContext context) {
    final live = [
      for (final e in events)
        if (EventStage.of(e.status) != EventStage.completed) e,
    ];
    if (live.isEmpty) return const SizedBox.shrink();

    // Three is enough to be useful; the events screen has the rest.
    final shown = live.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BrutSectionTitle('Your events'),
        const SizedBox(height: AppLayout.tight),
        for (var i = 0; i < shown.length; i++) ...[
          EventProgressBar(
            title: shown[i].title,
            stage: EventStage.of(shown[i].status),
            onTap: onOpen == null ? null : () => onOpen!(shown[i]),
          ),
          if (i != shown.length - 1) const SizedBox(height: AppLayout.tight),
        ],
      ],
    );
  }
}
