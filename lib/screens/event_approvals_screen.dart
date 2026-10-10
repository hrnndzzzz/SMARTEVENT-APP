import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'event_detail_screen.dart';
import 'events_screen.dart' show eventStatusTone;

/// Where every proposal got to.
///
/// The list screen is sorted by school year and answers "what is there".
/// This one is sorted by whose desk it is on and answers "what is
/// stuck" — which is the question anyone actually has when they open an
/// approvals screen two days before an event.
///
/// Both pending stages stay apart. An event waiting on the adviser is in
/// a different person's queue from one waiting on the admin, and folding
/// them into "pending" hides the only thing that tells you who to go and
/// talk to.
class EventApprovalsScreen extends StatelessWidget {
  const EventApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final events = app.events;

    List<EventItem> of(EventApprovalStatus status) =>
        events.where((e) => e.status == status).toList();

    final groups = <({
      String title,
      String blurb,
      EventApprovalStatus status,
      List<EventItem> items,
    })>[
      (
        title: 'With the adviser',
        blurb: 'Stage one of two. Only an adviser can move these.',
        status: EventApprovalStatus.pendingAdviser,
        items: of(EventApprovalStatus.pendingAdviser),
      ),
      (
        title: 'With the admin',
        blurb: 'Stage two. The adviser has already said yes.',
        status: EventApprovalStatus.pendingAdmin,
        items: of(EventApprovalStatus.pendingAdmin),
      ),
      (
        title: 'Came back',
        blurb: 'Rejected, with remarks. Editable and resubmittable.',
        status: EventApprovalStatus.rejected,
        items: of(EventApprovalStatus.rejected),
      ),
      (
        title: 'Approved',
        blurb: 'Through both stages.',
        status: EventApprovalStatus.approved,
        items: of(EventApprovalStatus.approved),
      ),
      (
        title: 'Completed',
        blurb: 'The settled end state. The backend sets this, not the app.',
        status: EventApprovalStatus.completed,
        items: of(EventApprovalStatus.completed),
      ),
      (
        title: 'Not submitted',
        blurb: 'Drafts. Nobody is waiting on these yet.',
        status: EventApprovalStatus.draft,
        items: of(EventApprovalStatus.draft),
      ),
    ];

    final waiting = of(EventApprovalStatus.pendingAdviser).length +
        of(EventApprovalStatus.pendingAdmin).length;

    return BrutScreen(
      header: BrutHeader(
        eyebrow: 'Events',
        title: 'Approvals',
        tone: waiting > 0 ? BrutTone.sun : BrutTone.teal,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Summary(waiting: waiting, total: events.length, groups: {
            for (final g in groups) g.status: g.items.length,
          }),
          const SizedBox(height: AppLayout.section),
          if (events.isEmpty)
            const Center(
              child: BrutEmptyState(
                icon: Icons.fact_check_outlined,
                title: 'No proposals yet',
                hint: 'Once one is submitted, this shows whose desk it is on.',
              ),
            )
          else
            for (final group in groups)
              if (group.items.isNotEmpty) ...[
                _Group(
                  title: group.title,
                  blurb: group.blurb,
                  status: group.status,
                  items: group.items,
                ),
                const SizedBox(height: AppLayout.section),
              ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.waiting,
    required this.total,
    required this.groups,
  });

  final int waiting;
  final int total;
  final Map<EventApprovalStatus, int> groups;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: waiting > 0 ? BrutTone.sun : BrutTone.mint,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$waiting',
                  style: AppText.heroNumber.copyWith(fontSize: 46),
                ),
                const SizedBox(height: 2),
                MonoLabel(
                  waiting == 1 ? 'Awaiting a decision' : 'Awaiting decisions',
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$total', style: AppText.moneyLarge.copyWith(fontSize: 20)),
              const SizedBox(height: 2),
              const MonoLabel('On record'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.blurb,
    required this.status,
    required this.items,
  });

  final String title;
  final String blurb;
  final EventApprovalStatus status;
  final List<EventItem> items;

  @override
  Widget build(BuildContext context) {
    final tone = eventStatusTone(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: tone.fill(context),
                shape: BoxShape.circle,
                border: Border.all(color: context.palette.ink, width: 2),
              ),
            ),
            const SizedBox(width: AppLayout.tight),
            Expanded(child: Text(title, style: AppText.sectionTitle)),
            MonoLabel('${items.length}'),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Text(blurb, style: AppText.caption),
        ),
        const SizedBox(height: AppLayout.between),
        for (var i = 0; i < items.length; i++) ...[
          BrutListRow(
            title: items[i].title,
            meta: '${items[i].org} · ${items[i].date}',
            marker: BrutIconTile(
              icon: switch (status) {
                EventApprovalStatus.rejected => Icons.undo,
                EventApprovalStatus.approved ||
                EventApprovalStatus.completed =>
                  Icons.check,
                EventApprovalStatus.draft => Icons.edit_outlined,
                _ => Icons.hourglass_top,
              },
              tone: tone,
              size: 32,
            ),
            trailing: Text(
              items[i].budget,
              style: AppText.number.copyWith(fontSize: 12),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EventDetailScreen(event: items[i]),
              ),
            ),
          ),
          if (i != items.length - 1) const SizedBox(height: AppLayout.tight),
        ],
      ],
    );
  }
}
