import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'create_event_screen.dart';

class EventDetailScreen extends StatelessWidget {
  final EventItem event;

  const EventDetailScreen({super.key, required this.event});

  Future<void> _openFeedbackDialog(BuildContext context) async {
    int rating = event.adviserRating ?? 3;
    final controller = TextEditingController(text: event.adviserComment ?? '');

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Post-Event Evaluation', style: AppText.cardTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Rating', style: AppText.caption),
              const SizedBox(height: 6),
              Row(
                children: List.generate(5, (i) {
                  final starIndex = i + 1;
                  return IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setDialogState(() => rating = starIndex),
                    icon: Icon(
                      starIndex <= rating ? Icons.star : Icons.star_border,
                      color: AppColors.marigold,
                      size: 26,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),
              const Text('Comments', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Official remarks about this event...'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                context.read<AppState>().submitFeedback(
                  event,
                  rating: rating,
                  comment: controller.text.trim(),
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Feedback saved.')),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

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
              ? (isAdviserStage ? 'Approve & Forward to Admin' : 'Grant Final Approval')
              : 'Reject Proposal',
          style: AppText.cardTitle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.title, style: AppText.body.copyWith(fontWeight: FontWeight.w500)),
            if (!isAdviserStage && event.adviserApprovalNote?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F2EC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Adviser note: "${event.adviserApprovalNote}"',
                  style: AppText.caption.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Feedback (optional)', style: AppText.caption),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: approved ? 'Any notes...' : 'Reason for rejection...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: approved ? AppColors.indigo : AppColors.brick,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(approved ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final app = context.read<AppState>();
      final String? error = isAdviserStage
          ? await app.adviserDecision(event, approved: approved, note: controller.text.trim())
          : await app.adminDecision(event, approved: approved, note: controller.text.trim());

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? '${event.title} — ${approved ? 'Approved' : 'Rejected'}')),
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
        final isOwnProposal = currentUserId != null &&
            event.proposedBy != null &&
            event.proposedBy == currentUserId;

        // Two-stage review: the Adviser resolves the adviser stage, an
        // Admin or Super Admin the admin stage. An Admin must not see
        // Approve while the event is still waiting on the adviser.
        final canAdviserDecide = !isOwnProposal &&
            role == UserRole.adviser &&
            event.status == EventApprovalStatus.pendingAdviser;
        final canAdminDecide = !isOwnProposal &&
            (role?.isAdministrator ?? false) &&
            event.status == EventApprovalStatus.pendingAdmin;

        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontFamily: AppText.headerFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 19,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('${event.org} · ${event.date}', style: AppText.caption),
                  const SizedBox(height: 18),
                  _ApprovalStatusCard(event: event),
                  if (canAdviserDecide || canAdminDecide) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _decide(context, approved: false, isAdviserStage: canAdviserDecide),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.brick, width: 0.8),
                              foregroundColor: AppColors.brick,
                            ),
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _decide(context, approved: true, isAdviserStage: canAdviserDecide),
                            child: const Text('Approve'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Event details', style: AppText.cardTitle),
                          const SizedBox(height: 10),
                          _detailRow('Venue', event.venue),
                          const SizedBox(height: 6),
                          _detailRow('Requested budget', event.budget, mono: true),
                          const SizedBox(height: 6),
                          _detailRow('Attendees', event.attendees),
                          const SizedBox(height: 6),
                          _detailRow('School year', event.academicLabel),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ApprovalTimelineCard(event: event),
                  const SizedBox(height: 14),
                  _AttendanceCard(event: event),
                  if (!(role?.isAdministrator ?? false)) ...[
                    const SizedBox(height: 14),
                    _FeedbackCard(
                      event: event,
                      onEdit: role == UserRole.adviser ? () => _openFeedbackDialog(context) : null,
                    ),
                  ],
                  // Editing a proposal belongs to whoever may propose one,
                  // and only while it is still draft or rejected. Officers
                  // are read-only and no longer get this button.
                  if ((role?.canProposeEvents ?? false) &&
                      event.status == EventApprovalStatus.rejected) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => CreateEventScreen(existingEvent: event)),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit Proposal'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value, {bool mono = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.caption),
        Text(
          value,
          style: TextStyle(
            fontFamily: mono ? AppText.monoFamily : AppText.bodyFamily,
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: AppColors.ink,
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

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Approval status', style: AppText.caption),
            const SizedBox(height: 14),
            if (isRejected)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBEAE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.cancel_outlined, size: 18, color: AppColors.brick),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Rejected by ${event.rejectedBy}', style: const TextStyle(fontFamily: AppText.headerFamily, fontWeight: FontWeight.w500, fontSize: 13, color: AppColors.brick)),
                          if ((event.rejectedBy == 'Adviser' ? event.adviserApprovalNote : event.adminApprovalNote)?.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              (event.rejectedBy == 'Adviser' ? event.adviserApprovalNote : event.adminApprovalNote)!,
                              style: AppText.caption.copyWith(height: 1.4),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _stageChip(
                      label: 'Adviser Review',
                      done: event.status != EventApprovalStatus.pendingAdviser,
                      current: event.status == EventApprovalStatus.pendingAdviser,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _stageChip(
                      label: 'Admin Approval',
                      done: event.status == EventApprovalStatus.approved,
                      current: event.status == EventApprovalStatus.pendingAdmin,
                    ),
                  ),
                ],
              ),
            if (!isRejected && event.adviserApprovalNote?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text('Adviser: "${event.adviserApprovalNote}"', style: AppText.caption.copyWith(fontStyle: FontStyle.italic)),
            ],
            if (!isRejected && event.adminApprovalNote?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text('Admin: "${event.adminApprovalNote}"', style: AppText.caption.copyWith(fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stageChip({required String label, required bool done, required bool current}) {
    final color = done ? AppColors.sageTeal : (current ? AppColors.marigold : AppColors.inkFaint);
    final bg = done ? AppColors.sageTealTint : (current ? AppColors.marigoldTint : const Color(0xFFF4F2EC));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Icon(
            done ? Icons.check_circle : (current ? Icons.hourglass_top : Icons.radio_button_unchecked),
            size: 16,
            color: color,
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 10, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final EventItem event;
  const _AttendanceCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final expected = event.expectedAttendees;
    final progress = expected == 0 ? 0.0 : (event.checkedIn / expected).clamp(0.0, 1.0);
    final app = context.read<AppState>();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Attendance', style: AppText.cardTitle),
                if (event.checkedIn > 0)
                  GestureDetector(
                    onTap: () => app.resetAttendance(event),
                    child: const Text('Reset', style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 11, color: AppColors.inkMuted)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${event.checkedIn}',
                        style: const TextStyle(
                          fontFamily: AppText.monoFamily,
                          fontWeight: FontWeight.w500,
                          fontSize: 22,
                          color: AppColors.ink,
                        ),
                      ),
                      TextSpan(
                        text: expected > 0 ? ' / $expected checked in' : ' checked in',
                        style: const TextStyle(fontFamily: AppText.bodyFamily, fontSize: 12, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => app.checkInAttendee(event),
                  icon: const Icon(Icons.person_add_alt_1, size: 15),
                  label: const Text('Check In', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                ),
              ],
            ),
            if (expected > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: AppColors.trackBg,
                  color: AppColors.sageTeal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final EventItem event;
  final VoidCallback? onEdit;

  const _FeedbackCard({required this.event, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Post-Event Evaluation', style: AppText.cardTitle),
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: Icon(event.hasFeedback ? Icons.edit_outlined : Icons.add, size: 15),
                    label: Text(event.hasFeedback ? 'Edit' : 'Add', style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!event.hasFeedback)
              const Text('No evaluation submitted yet.', style: AppText.caption)
            else ...[
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < (event.adviserRating ?? 0) ? Icons.star : Icons.star_border,
                    color: AppColors.marigold,
                    size: 16,
                  );
                }),
              ),
              if (event.adviserComment != null && event.adviserComment!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(event.adviserComment!, style: AppText.caption.copyWith(height: 1.4)),
              ],
            ],
          ],
        ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Review history', style: AppText.cardTitle),
              ),
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _body(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Text(
        _error!,
        style: AppText.caption.copyWith(color: AppColors.brick),
      );
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

  Color get _decisionColor => switch (record.decision) {
        'approved' => AppColors.sageTeal,
        'rejected' => AppColors.brick,
        _ => AppColors.marigold,
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
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: _decisionColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Step ${record.stepOrder}',
                    style: AppText.caption.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _decisionLabel,
                    style: AppText.caption.copyWith(color: _decisionColor),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(_when, style: AppText.caption),
              if (record.reviewerId != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Reviewer ${record.reviewerId}',
                  style: const TextStyle(
                    fontFamily: AppText.bodyFamily,
                    fontSize: 10,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
              if (record.remarks?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
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
