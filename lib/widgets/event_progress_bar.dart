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
/// whether it is waiting on someone, turned down, or done.
///
/// Red means it was rejected, and a rejection is final. Amber means
/// someone else has it. Green means it is through.
enum EventStage {
  drafting('Drafting', 0),
  rejected('Rejected', 1),
  withModerator('With the Moderator', 2),
  withDean('With the Dean', 3),
  withSds('With the SDS Office', 4),
  approved('Approved', 5),
  completed('Completed', 5);

  const EventStage(this.label, this.reached);

  final String label;

  /// How many of the four segments are filled. `index` is already an
  /// enum's own member, hence the name.
  final int reached;

  static const int segments = 5;

  BrutTone get tone => switch (this) {
    EventStage.drafting => BrutTone.neutral,
    EventStage.rejected => BrutTone.coral,
    EventStage.withModerator ||
    EventStage.withDean ||
    EventStage.withSds => BrutTone.sun,
    EventStage.approved || EventStage.completed => BrutTone.mint,
  };

  /// What the person looking at it should do, if anything.
  String get note => switch (this) {
    EventStage.drafting => 'Not submitted yet',
    EventStage.rejected => 'Final. Start a new proposal',
    EventStage.withModerator => 'Waiting on your Moderator',
    EventStage.withDean => 'Waiting on the Dean',
    // True of all of it: the event stays here after the office has signed,
    // while the paper goes round, until the final scan. Kept short because
    // it is set on one line.
    EventStage.withSds => 'Review, signing, then nine signatures',
    EventStage.approved => 'Ready to run',
    EventStage.completed => 'Closed out',
  };

  /// Each desk is named rather than collapsed into "with the reviewers".
  ///
  /// The proposer can do nothing differently whichever desk has it, which
  /// was the old argument for saying nothing. But they can see that it
  /// moved, and a proposal that sat with the moderator for a week is a
  /// different thing from one that reached the SDS Office yesterday.
  static EventStage of(EventApprovalStatus status) => switch (status) {
    EventApprovalStatus.draft => EventStage.drafting,
    EventApprovalStatus.pendingAdviser => EventStage.withModerator,
    EventApprovalStatus.pendingAdmin => EventStage.withDean,
    EventApprovalStatus.pendingInstitutional => EventStage.withSds,
    EventApprovalStatus.rejected => EventStage.rejected,
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

    // Foldable, because someone with nothing outstanding should be able
    // to put it away and see the money underneath without scrolling.
    return BrutFoldable(
      title: 'Your events',
      count: live.length,
      children: [
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

/// Every live event's progress, for a peek.
///
/// The same bars [EventProgressList] draws, without the fold or the
/// three-item cut: a glance is where you want all of them, because the
/// reason for holding is to see where everything has got to at once.
class EventProgressPeek extends StatelessWidget {
  const EventProgressPeek({super.key, required this.events, this.onOpen});

  final List<EventItem> events;
  final void Function(EventItem)? onOpen;

  @override
  Widget build(BuildContext context) {
    // Grouped by where they have got to, furthest along last, so the
    // ones still needing something sit together at the top rather than
    // being scattered through whatever order the list arrived in.
    final live =
        [
          for (final e in events)
            if (EventStage.of(e.status) != EventStage.completed) e,
        ]..sort((a, b) {
          final byStage = EventStage.of(
            a.status,
          ).index.compareTo(EventStage.of(b.status).index);
          // Same stage: soonest first, so the group reads as a queue.
          if (byStage != 0) return byStage;
          if (a.on == null && b.on == null) return 0;
          if (a.on == null) return 1;
          if (b.on == null) return -1;
          return a.on!.compareTo(b.on!);
        });
    if (live.isEmpty) {
      return const Text(
        'Nothing is in progress. Everything on record is finished.',
        style: AppText.body,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < live.length; i++) ...[
          EventProgressBar(
            title: live[i].title,
            stage: EventStage.of(live[i].status),
            onTap: onOpen == null ? null : () => onOpen!(live[i]),
          ),
          if (i != live.length - 1) const SizedBox(height: AppLayout.tight),
        ],
      ],
    );
  }
}
