import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models/sap_proposal.dart';
import '../state/app_state.dart';
import '../state/demo_data.dart';
import '../state/sap_form.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import 'sap/sds_summary_screen.dart';

/// The proposals the SDS Office has work on.
///
/// SDS owns Part 4, the paper checkpoints, the return, the final scan and
/// Part 6 — all of them reached through an event. The role is otherwise
/// held to proposal letters, which left that work with no way to it: the
/// office could be asked to sign something it could not open.
class SdsProposalsScreen extends StatelessWidget {
  const SdsProposalsScreen({super.key});

  /// Where a proposal has got to, said in the words the office uses
  /// rather than the enum's.
  static (String, BrutTone) stageOf(EventApprovalStatus status) =>
      switch (status) {
        EventApprovalStatus.draft => ('Still being written', BrutTone.neutral),
        EventApprovalStatus.pendingAdviser => (
          'With the moderator',
          BrutTone.sun,
        ),
        EventApprovalStatus.pendingAdmin => ('With the Dean', BrutTone.sun),
        EventApprovalStatus.pendingInstitutional => (
          'With the SDS Office',
          BrutTone.sun,
        ),
        EventApprovalStatus.approved => ('Approved', BrutTone.mint),
        EventApprovalStatus.rejected => ('Rejected', BrutTone.coral),
        EventApprovalStatus.completed => ('Completed', BrutTone.mint),
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    // A draft has not been sent anywhere, so it is nobody's to review.
    final waiting = [
      for (final event in app.events)
        if (event.status != EventApprovalStatus.draft) event,
    ];

    return BrutScreen(
      header: BrutHeader(
        title: 'Proposals',
        eyebrow: 'SDS Office',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            waiting.isEmpty
                ? 'Nothing has been submitted yet.'
                : '${waiting.length} submitted across the school.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          if (waiting.isEmpty)
            const BrutEmptyState(
              icon: Icons.inbox_outlined,
              title: 'No proposals yet',
              hint: 'They appear here once an organization submits one.',
            )
          else
            for (final event in waiting) ...[
              _ProposalCard(event: event),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.event});

  final EventItem event;

  @override
  Widget build(BuildContext context) {
    final (stage, tone) = SdsProposalsScreen.stageOf(event.status);

    return BrutCard(
      onTap: () {
        final app = context.read<AppState>();
        final form = SapForm(
          eventId: event.remoteId ?? '',
          service: app.isDemoMode ? null : app.sapService,
        );
        if (app.isDemoMode) {
          form.seedLocally(
            state: _sapStateFor(event.status),
            details: DemoProposals.detailsFor(event),
            returnRemarks: DemoProposals.returnRemarksFor(event),
          );
          form.setBudgetItems(DemoProposals.budgetFor(event));
          form.setSupportRequests(DemoProposals.supportFor(event));
        }
        // The summary, not the six-part form. The office reads this and
        // decides; it does not fill it in.
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => SdsSummaryScreen(form: form)),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  event.title,
                  style: AppText.cardTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              BrutBadge(label: stage, tone: tone),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${event.org} · ${event.date}',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }

  /// The proposal's own state, from how far the event has got. The demo
  /// has no server, so this is the only timeline it knows.
  SapState _sapStateFor(EventApprovalStatus status) => switch (status) {
    EventApprovalStatus.draft => SapState.draft,
    EventApprovalStatus.pendingAdviser ||
    EventApprovalStatus.pendingAdmin => SapState.pendingDepartmentReview,
    EventApprovalStatus.pendingInstitutional => SapState.pendingReview,
    EventApprovalStatus.rejected => SapState.rejected,
    EventApprovalStatus.approved => SapState.approved,
    EventApprovalStatus.completed => SapState.completed,
  };
}
