import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import 'sap/sap_form_screen.dart';
import 'sap/sap_proposal_flow.dart';
import '../state/sap_form.dart';
import '../widgets/event_status.dart';
import '../api/compliance_service.dart';
import '../api/models/compliance.dart';
import '../api/models/sap_proposal.dart';
import 'event_readiness_screen.dart';

class EventDetailScreen extends StatelessWidget {
  final EventItem event;

  const EventDetailScreen({super.key, required this.event});

  Future<void> _decide(
    BuildContext context, {
    required bool approved,
    required bool isAdviserStage,
  }) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          approved
              ? (isAdviserStage
                    ? 'Approve and forward to admin'
                    : 'Grant final approval')
              : 'Reject proposal',
          style: AppText.cardTitle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.title,
              style: AppText.body.copyWith(fontWeight: FontWeight.w700),
            ),
            if (!isAdviserStage &&
                event.adviserApprovalNote?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              BrutInlineMessage(
                text: 'Adviser note: "${event.adviserApprovalNote}"',
                tone: BrutTone.neutral,
                icon: Icons.chat_bubble_outline,
              ),
            ],
            const SizedBox(height: 14),
            BrutTextField(
              label: 'Feedback (optional)',
              controller: controller,
              maxLines: 3,
              hint: approved ? 'Any notes…' : 'Reason for rejection…',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          BrutButton(
            label: approved ? 'Approve' : 'Reject',
            expand: false,
            size: BrutSize.small,
            tone: approved ? BrutTone.mint : BrutTone.coral,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final app = context.read<AppState>();
      final String? error = isAdviserStage
          ? await app.adviserDecision(
              event,
              approved: approved,
              note: controller.text.trim(),
            )
          : await app.adminDecision(
              event,
              approved: approved,
              note: controller.text.trim(),
            );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error ?? '${event.title} — ${approved ? 'Approved' : 'Rejected'}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        final role = app.currentRole;

        // Nobody reviews their own proposal. The API enforces this too, so
        // this only avoids offering a button that is certain to 403.
        final currentUserId = app.currentAccount?.id;
        final isOwnProposal =
            currentUserId != null &&
            event.proposedBy != null &&
            event.proposedBy == currentUserId;

        // Two-stage review: the Adviser resolves the adviser stage, an
        // Admin or Super Admin the admin stage. An Admin must not see
        // Approve while the event is still waiting on the adviser.
        final canAdviserDecide =
            !isOwnProposal &&
            role == UserRole.adviser &&
            event.status == EventApprovalStatus.pendingAdviser;
        final canAdminDecide =
            !isOwnProposal &&
            (role?.isAdministrator ?? false) &&
            event.status == EventApprovalStatus.pendingAdmin;

        return BrutScreen(
          header: BrutHeader(
            eyebrow: '${event.org} · ${event.date}',
            title: event.title,
            tone: eventStatusTone(event.status),
            onBack: () => Navigator.of(context).maybePop(),
            action: BrutBadge(
              label: event.statusLabel,
              tone: eventStatusTone(event.status),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ApprovalStatusCard(event: event),
              if (canAdviserDecide || canAdminDecide) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: BrutButton(
                        label: 'Reject',
                        tone: BrutTone.coral,
                        onPressed: () => _decide(
                          context,
                          approved: false,
                          isAdviserStage: canAdviserDecide,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BrutButton(
                        label: 'Approve',
                        tone: BrutTone.mint,
                        onPressed: () => _decide(
                          context,
                          approved: true,
                          isAdviserStage: canAdviserDecide,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              BrutCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrutSectionTitle('Event details'),
                    const SizedBox(height: 12),
                    _detailRow('Requested budget', event.budget, mono: true),
                    const SizedBox(height: 8),
                    _detailRow('School year', event.academicLabel),
                  ],
                ),
              ),
              // What is in the way, on the screen where the question is
              // asked. A button called Before approval answered nothing
              // until you pressed it; this says the first blocker and
              // then offers to go and clear it.
              if (app.mayProposeEvents || (role?.canReview ?? false)) ...[
                const SizedBox(height: 14),
                _ReadinessNotice(event: event),
              ],

              // Taking your own proposal back, while it is still anyone's
              // to decide on. Once it has been approved or returned the
              // decision is the record, and withdrawing it would erase
              // someone else's.
              if (app.mayProposeEvents && event.status.isPending) ...[
                const SizedBox(height: 14),
                BrutButton(
                  label: 'Cancel this proposal',
                  icon: Icons.undo,
                  tone: BrutTone.coral,
                  onPressed: () => _cancelProposal(context, event),
                ),
              ],
              const SizedBox(height: 14),
              _ApprovalTimelineCard(event: event),
              // Editing a proposal belongs to whoever may
              // propose one, and only while it is still draft or
              // rejected. Officers are read-only and no longer
              // get this button.
              // The SAS-SDS-FO-020 form. Offered on any event the backend
              // knows about: the proposer fills Parts 1 to 3 and the SDS
              // Office the rest, and which of those a given person may do
              // is the API's call to make, not a button's. An event that
              // has never reached the server has nothing to hang a
              // proposal on.
              if (event.remoteId case final eventId?) ...[
                const SizedBox(height: 14),
                BrutButton(
                  label: 'Proposal form',
                  icon: Icons.description_outlined,
                  tone: BrutTone.neutral,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      // The SDS Office works all six parts. Everyone else
                      // only ever fills the first three, and a six-part
                      // list hands them three they cannot touch.
                      builder: (_) {
                        final app = context.read<AppState>();
                        final form = SapForm(
                          eventId: eventId,
                          service: app.isDemoMode ? null : app.sapService,
                        );
                        // The demo has no server, so the form would hold
                        // no proposal and sit at a null state — which
                        // locks Parts 5 and 6 and hides review and
                        // signing. Seed it from where the event itself
                        // has got to, so the SDS role can see the six
                        // parts it is offered.
                        if (app.isDemoMode) {
                          form.seedLocally(state: _demoSapState(event.status));
                        }
                        return SapFormScreen(form: form);
                      },
                    ),
                  ),
                ),
              ],
              if (app.mayProposeEvents &&
                  event.status == EventApprovalStatus.rejected) ...[
                const SizedBox(height: 14),
                BrutButton(
                  label: 'Edit proposal',
                  icon: Icons.edit_outlined,
                  tone: BrutTone.neutral,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SapFormScreen(
                        form: SapForm(
                          eventId: event.remoteId,
                          service: context.read<AppState>().isDemoMode
                              ? null
                              : context.read<AppState>().sapService,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value, {bool mono = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: MonoLabel(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: mono
                ? AppText.number
                : AppText.body.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Replaces the old ambiguous 4-step timeline with a clear 2-stage
/// approval trail: Adviser Review -> Admin Approval, with a distinct
/// rejected state that names who rejected it and why.
class _ApprovalStatusCard extends StatelessWidget {
  final EventItem event;
  const _ApprovalStatusCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final isRejected = event.status == EventApprovalStatus.rejected;
    final rejectionNote = event.rejectedBy == 'Adviser'
        ? event.adviserApprovalNote
        : event.adminApprovalNote;

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrutSectionTitle('Approval status'),
          const SizedBox(height: 14),
          if (isRejected)
            BrutInlineMessage(
              tone: BrutTone.coral,
              icon: Icons.cancel_outlined,
              // The reviewer is not always known — a legacy row, or one
              // rejected before the field existed, carries none. Saying
              // "Rejected by null" is worse than not naming anyone.
              text: [
                event.rejectedBy?.isNotEmpty == true
                    ? 'Rejected by ${event.rejectedBy}.'
                    : 'This proposal was rejected.',
                if (rejectionNote?.isNotEmpty == true) rejectionNote!,
              ].join(' '),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _StageChip(
                    label: 'Adviser review',
                    // Past it, not merely not in it. A draft is not in
                    // adviser review either, and used to tick green here
                    // the moment a proposal was taken back.
                    done: switch (event.status) {
                      EventApprovalStatus.pendingAdmin ||
                      EventApprovalStatus.pendingInstitutional ||
                      EventApprovalStatus.approved ||
                      EventApprovalStatus.completed => true,
                      _ => false,
                    },
                    current: event.status == EventApprovalStatus.pendingAdviser,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StageChip(
                    label: 'Admin approval',
                    done:
                        event.status == EventApprovalStatus.approved ||
                        event.status == EventApprovalStatus.completed,
                    current: event.status == EventApprovalStatus.pendingAdmin,
                  ),
                ),
              ],
            ),
          if (!isRejected && event.adviserApprovalNote?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              'Adviser: "${event.adviserApprovalNote}"',
              style: AppText.caption.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          if (!isRejected && event.adminApprovalNote?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              'Admin: "${event.adminApprovalNote}"',
              style: AppText.caption.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({
    required this.label,
    required this.done,
    required this.current,
  });

  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    // Done is green, waiting is yellow, not reached is flat grey with no
    // shadow — a stage nobody is holding should not look like a control.
    final tone = done
        ? BrutTone.mint
        : current
        ? BrutTone.sun
        : BrutTone.neutral;
    final reached = done || current;

    return BrutSurface(
      fill: reached ? tone.fill(context) : context.palette.line,
      radius: AppRadius.rowAll,
      shadow: reached ? AppShadows.sm : AppShadows.none,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Column(
        children: [
          Icon(
            done
                ? Icons.check_circle
                : current
                ? Icons.hourglass_top
                : Icons.radio_button_unchecked,
            size: 18,
            color: reached ? context.palette.ink : context.palette.muted,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.buttonLabel.copyWith(
              fontSize: 11,
              color: reached ? context.palette.ink : context.palette.subtle,
            ),
          ),
        ],
      ),
    );
  }
}

/// The real review history from `GET /events/{id}/approvals`: who decided
/// what, when, and any remarks.
///
/// This is separate from the two stage chips above, which only summarise
/// where the event sits now. The backend returns reviewer IDs rather than
/// names, and fetching `/users` to decorate them would 403 for most roles,
/// so the ID is shown as-is until a name-display change is agreed.
class _ApprovalTimelineCard extends StatefulWidget {
  const _ApprovalTimelineCard({required this.event});

  final EventItem event;

  @override
  State<_ApprovalTimelineCard> createState() => _ApprovalTimelineCardState();
}

class _ApprovalTimelineCardState extends State<_ApprovalTimelineCard> {
  List<ApprovalRecord>? _records;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final outcome = await context.read<AppState>().loadApprovals(widget.event);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _records = outcome.records;
      _error = outcome.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrutSectionTitle(
            'Review history',
            aside: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: BrutSpinner(size: 14),
                  )
                : BrutIconButton(
                    icon: Icons.refresh,
                    label: 'Reload review history',
                    size: 30,
                    onPressed: _load,
                  ),
          ),
          const SizedBox(height: 12),
          _body(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return BrutInlineMessage(text: _error!, tone: BrutTone.coral);
    }

    final records = _records;
    if (records == null) {
      return const Text('Loading…', style: AppText.caption);
    }
    if (records.isEmpty) {
      // Genuinely no decisions yet — distinct from a failed load above.
      return const Text(
        'No review decisions recorded yet.',
        style: AppText.caption,
      );
    }

    // Step order is the backend's own sequence; don't re-sort by time,
    // which can tie or be null on pending steps.
    final ordered = [...records]
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final record in ordered) ...[
          _ApprovalRow(record: record),
          if (record != ordered.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({required this.record});

  final ApprovalRecord record;

  BrutTone get _tone => switch (record.decision) {
    'approved' => BrutTone.mint,
    'rejected' => BrutTone.coral,
    _ => BrutTone.sun,
  };

  String get _decisionLabel => switch (record.decision) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'pending' => 'Awaiting decision',
    final other => other,
  };

  String get _when {
    final decidedAt = record.decidedAt;
    if (decidedAt == null) return 'Not yet decided';
    final local = decidedAt.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            color: _tone.fill(context),
            shape: BoxShape.circle,
            border: Border.all(color: context.palette.ink, width: 1.5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MonoLabel('Step ${record.stepOrder}'),
                  const SizedBox(width: 8),
                  Text(
                    _decisionLabel,
                    style: AppText.body.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(_when, style: AppText.moneySmall),
              if (record.reviewerId != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Reviewer ${record.reviewerId}',
                  style: AppText.caption.copyWith(
                    fontSize: 10,
                    color: context.palette.muted,
                  ),
                ),
              ],
              if (record.remarks?.isNotEmpty == true) ...[
                const SizedBox(height: 5),
                Text(
                  '“${record.remarks}”',
                  style: AppText.caption.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Why this event cannot be approved yet, inline.
///
/// It asks the backend for the same blockers the approval refusal
/// carries, and shows the first with a count of the rest. A deployment
/// without the route says nothing at all rather than claiming the event
/// is ready — silence is the honest answer when there is nothing to ask.
class _ReadinessNotice extends StatefulWidget {
  const _ReadinessNotice({required this.event});

  final EventItem event;

  @override
  State<_ReadinessNotice> createState() => _ReadinessNoticeState();
}

class _ReadinessNoticeState extends State<_ReadinessNotice> {
  EventReadiness? _readiness;
  bool _unavailable = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.event.remoteId;
    if (id == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final result = await context.read<AppState>().eventReadiness(id);
      if (mounted)
        setState(() {
          _readiness = result;
          _loading = false;
        });
    } on FeatureUnavailable {
      if (mounted)
        setState(() {
          _unavailable = true;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFull() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventReadinessScreen(event: widget.event),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _unavailable) return const SizedBox.shrink();

    final readiness = _readiness;
    if (readiness == null) return const SizedBox.shrink();

    if (readiness.ready) {
      return BrutCard(
        tone: BrutTone.mint,
        radius: AppRadius.rowAll,
        padding: const EdgeInsets.all(12),
        onTap: _openFull,
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ready for approval.',
                style: AppText.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      );
    }

    final first = readiness.blockers.first;
    final more = readiness.blockers.length - 1;
    return BrutCard(
      tone: BrutTone.coral,
      radius: AppRadius.rowAll,
      padding: const EdgeInsets.all(12),
      onTap: _openFull,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.priority_high, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not ready for approval',
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(first, style: AppText.caption),
                if (more > 0) ...[
                  const SizedBox(height: 4),
                  MonoLabel('and $more more'),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }
}



/// Confirms, then takes the proposal back to draft.
Future<void> _cancelProposal(BuildContext context, EventItem event) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Take this proposal back?'),
      content: Text(
        '"${event.title}" goes back to a draft and leaves the reviewers\' '
        'queue. Nothing you have written is lost, and you can submit it '
        'again when it is ready.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Leave it'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Take it back'),
        ),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;

  final problem = await context.read<AppState>().cancelProposal(event);
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(problem ?? 'Back with you as a draft.')),
  );
}

/// Where the proposal form sits, for an event in the offline demo.
///
/// The event's own approval status is the only thing the demo knows, so
/// the form follows it rather than inventing a second timeline.
SapState _demoSapState(EventApprovalStatus status) => switch (status) {
  EventApprovalStatus.draft => SapState.draft,
  EventApprovalStatus.pendingAdviser ||
  EventApprovalStatus.pendingAdmin ||
  EventApprovalStatus.pendingInstitutional => SapState.pendingReview,
  EventApprovalStatus.rejected => SapState.revisionRequested,
  EventApprovalStatus.approved => SapState.approved,
  EventApprovalStatus.completed => SapState.completed,
};
