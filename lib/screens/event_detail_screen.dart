import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../state/demo_data.dart';
import 'event_report_screen.dart';
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

  /// [isProposal] is whether the event carries a SAP proposal, where not
  /// approving is a return for revision that must say what to change; on
  /// any other event it is a rejection with an optional note.
  /// [expectedVersion] is the proposal version the reviewer read, sent back
  /// so a proposal that changed meanwhile is refused.
  ///
  /// [note] opens the dialog already written. The answer says whether the
  /// proposal had changed, and what to open the dialog with next time: what
  /// was typed if the decision did not go through, so that a long reason is
  /// not lost to a refusal, and nothing otherwise.
  Future<({bool changed, String kept})> _decide(
    BuildContext context, {
    required bool approved,
    required bool isAdviserStage,
    required bool isProposal,
    int? expectedVersion,
    String note = '',
  }) async {
    final isReturn = isProposal && !approved;
    final controller = TextEditingController(text: note);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          approved
              // A proposal goes on to the next step; only a plain event ends
              // with this approval.
              ? (isAdviserStage
                    ? (isProposal
                          ? 'Approve and send to the Dean'
                          : 'Approve and forward to admin')
                    : (isProposal
                          ? 'Approve and send to the SDS Office'
                          : 'Grant final approval'))
              : isReturn
              ? 'Return for revision?'
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
              label: isReturn ? 'What needs changing' : 'Feedback (optional)',
              controller: controller,
              maxLines: 3,
              maxLength: 2000,
              hint: approved
                  ? 'Any notes…'
                  : isReturn
                  ? 'What the organization should fix…'
                  : 'Reason for rejection…',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          // A return without a reason would leave the organization guessing
          // (the server refuses it too), so it waits for one.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => BrutButton(
              label: approved
                  ? 'Approve'
                  : isReturn
                  ? 'Return'
                  : 'Reject',
              expand: false,
              size: BrutSize.small,
              tone: approved ? BrutTone.mint : BrutTone.coral,
              onPressed: isReturn && value.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return (changed: false, kept: '');

    final app = context.read<AppState>();
    // A blank note is no note: nothing is sent for it.
    final text = controller.text.trim();
    final result = isAdviserStage
        ? await app.adviserDecision(
            event,
            approved: approved,
            note: text.isEmpty ? null : text,
            expectedVersion: expectedVersion,
          )
        : await app.adminDecision(
            event,
            approved: approved,
            note: text.isEmpty ? null : text,
            expectedVersion: expectedVersion,
          );

    if (context.mounted) {
      final outcome = approved
          ? 'Approved'
          : isReturn
          ? 'Returned for revision'
          : 'Rejected';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? '${event.title} — $outcome')),
      );
    }
    return (changed: result.changed, kept: result.error == null ? '' : text);
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
            !app.isOfflineViewing &&
            !isOwnProposal &&
            role == UserRole.adviser &&
            event.status == EventApprovalStatus.pendingAdviser;
        final canAdminDecide =
            !app.isOfflineViewing &&
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
                _DecisionRow(
                  event: event,
                  onDecide:
                      ({
                        required bool approved,
                        required bool isProposal,
                        int? expectedVersion,
                        required String note,
                      }) => _decide(
                        context,
                        approved: approved,
                        isAdviserStage: canAdviserDecide,
                        isProposal: isProposal,
                        expectedVersion: expectedVersion,
                        note: note,
                      ),
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
              //
              // Your own: this asked only whether the account may propose
              // at all, so a reviewer opening someone else's submission
              // was offered the withdrawal — which the server refuses,
              // since the route is the proposer's. Where the proposer is
              // not known at all the capability is still the best guess,
              // rather than hiding the action from the person whose
              // proposal it is.
              if ((isOwnProposal || event.proposedBy == null) &&
                  app.mayProposeEvents &&
                  event.status.isPending) ...[
                const SizedBox(height: 14),
                BrutButton(
                  label: 'Cancel this proposal',
                  icon: Icons.undo,
                  tone: BrutTone.coral,
                  onPressed: app.isOfflineViewing
                      ? null
                      : () => _cancelProposal(context, event),
                ),
              ],
              const SizedBox(height: 14),
              _ApprovalTimelineCard(event: event),
              // The SAS-SDS-FO-020 form. Offered on any event the backend
              // knows about: the proposer fills Parts 1 to 3 and the SDS
              // Office the rest, and which of those a given person may do
              // is the API's call to make, not a button's. An event that
              // has never reached the server has nothing to hang a
              // proposal on.
              //
              // The only way into a proposal, a rejected one included: it
              // opens on the rejection and the SDS Office's reasons, and
              // nothing on it can be edited. A second button for rejected
              // events opened a blank, editable form in the demo.
              if (event.remoteId case final eventId?) ...[
                const SizedBox(height: 14),
                BrutButton(
                  label: 'Proposal form',
                  icon: Icons.description_outlined,
                  tone: BrutTone.neutral,
                  onPressed: () {
                    // Made here, once. A route's builder runs again on
                    // every app rebuild, and a form made there was
                    // swapped for one that never loaded.
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
                    //
                    // The contents too, and from the same place the
                    // SDS Office reads: seeding only the state left
                    // the proposer's own form empty while the office
                    // was looking at a full proposal for the very
                    // same event. An event the demo does not seed
                    // still opens blank, which is right.
                    if (app.isDemoMode) {
                      form.seedLocally(
                        state: _demoSapState(event.status),
                        details: DemoProposals.detailsFor(event),
                        sdsRemarks: DemoProposals.sdsRemarksFor(event),
                        clearance: DemoProposals.clearanceFor(event),
                      );
                      form.setBudgetItems(DemoProposals.budgetFor(event));
                      form.setSupportRequests(DemoProposals.supportFor(event));
                    }
                    // The SDS Office works all six parts. Everyone else
                    // only ever fills the first three, and a six-part
                    // list hands them three they cannot touch.
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => SapFormScreen(form: form)),
                    );
                  },
                ),
              ],
              // The event's own finances: what it was allowed, what came
              // in, what went out. The backend has answered this all
              // along and no screen opened it, so it had never been
              // seen. Only once the event is real and past approval —
              // a liquidation of a draft reports nothing.
              if (event.remoteId != null && event.status.isResolved) ...[
                const SizedBox(height: 14),
                BrutButton(
                  label: 'Financial report',
                  icon: Icons.receipt_long_outlined,
                  tone: BrutTone.neutral,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EventReportScreen(event: event),
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

/// What the Moderator or the Dean can do with the event: approve it, or
/// turn it down.
///
/// Turning down depends on what the event is. A SAP proposal is sent back
/// for revision, with a reason, and the Moderator and the Dean never reject
/// one; any other event is rejected, as it always was. So the proposal is
/// read here: it says which of the two to offer, and its version is what the
/// decision sends back, so that a proposal someone changed since is refused
/// instead of decided blind.
///
/// A refusal for that reason leaves the row stale: the version it holds is
/// out of date, so sending again would only be refused again, or worse
/// accepted over changes nobody has looked at. It offers to read the
/// proposal again and waits for that, as the SDS review screen does.
class _DecisionRow extends StatefulWidget {
  const _DecisionRow({required this.event, required this.onDecide});

  final EventItem event;
  final Future<({bool changed, String kept})> Function({
    required bool approved,
    required bool isProposal,
    int? expectedVersion,
    required String note,
  })
  onDecide;

  @override
  State<_DecisionRow> createState() => _DecisionRowState();
}

class _DecisionRowState extends State<_DecisionRow> {
  bool _loading = true;
  bool _isProposal = false;
  int? _version;
  String? _error;
  bool _stale = false;

  /// What was typed for each decision (keyed by whether it approves) and not
  /// sent, offered again the next time that dialog opens.
  final Map<bool, String> _kept = {};

  @override
  void initState() {
    super.initState();
    // The demo takes the same path: `proposalVersionFor` answers it from
    // the seed rather than the server, so a seeded proposal reports a
    // version and an event without one reports nothing. Short-circuiting
    // it here used to claim every demo event had a proposal while leaving
    // the version null, which turned every return into a rejection.
    _load();
  }

  Future<void> _load({bool refreshEvent = false}) async {
    final app = context.read<AppState>();
    try {
      // A decision refused because the event moved on is not cured by the
      // proposal's version: the status is what decides whether this row is
      // still offered, so a reload reads that too, and the row goes if it is
      // no longer this reviewer's turn.
      if (refreshEvent) await app.refreshEventStatus(widget.event);
      final version = await app.proposalVersionFor(widget.event);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _stale = false;
        _isProposal = version != null;
        _version = version;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = app.describeFailure(error);
      });
    }
  }

  void _reload() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load(refreshEvent: true);
  }

  Future<void> _decide(bool approved) async {
    final result = await widget.onDecide(
      approved: approved,
      isProposal: _isProposal,
      expectedVersion: _version,
      note: _kept[approved] ?? '',
    );
    if (!mounted) return;
    setState(() {
      _kept[approved] = result.kept;
      if (result.changed) _stale = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutInlineMessage(text: _error!, tone: BrutTone.coral),
          const SizedBox(height: 10),
          BrutButton(
            label: 'Try again',
            tone: BrutTone.neutral,
            onPressed: _reload,
          ),
        ],
      );
    }

    VoidCallback? decide(bool approved) =>
        _loading || _stale ? null : () => _decide(approved);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_stale) ...[
          const BrutInlineMessage(
            tone: BrutTone.coral,
            icon: Icons.sync_problem,
            text:
                'Someone else changed this proposal. Reload it to see their '
                'version before deciding.',
          ),
          const SizedBox(height: 10),
          BrutButton(
            label: 'Reload the proposal',
            tone: BrutTone.neutral,
            busy: _loading,
            busyLabel: 'Reloading',
            onPressed: _reload,
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Expanded(
              child: BrutButton(
                label: _isProposal ? 'Return for revision' : 'Reject',
                tone: BrutTone.coral,
                onPressed: decide(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BrutButton(
                label: 'Approve',
                tone: BrutTone.mint,
                onPressed: decide(true),
              ),
            ),
          ],
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
                    // Institutional review follows the admin's approval, in
                    // both flows.
                    done:
                        event.status ==
                            EventApprovalStatus.pendingInstitutional ||
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
    'rejected' || 'returned' => BrutTone.coral,
    _ => BrutTone.sun,
  };

  String get _decisionLabel => switch (record.decision) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'returned' => 'Returned for revision',
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
                  // Flexible: "Returned for revision" is longer than the
                  // other labels and ran off the end of a narrow card.
                  Flexible(
                    child: Text(
                      _decisionLabel,
                      style: AppText.body.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
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
  EventApprovalStatus.pendingAdmin => SapState.pendingDepartmentReview,
  EventApprovalStatus.pendingInstitutional => SapState.pendingReview,
  EventApprovalStatus.rejected => SapState.rejected,
  EventApprovalStatus.approved => SapState.approved,
  EventApprovalStatus.completed => SapState.completed,
};
