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
      if (isAdviserStage) {
        app.adviserDecision(event, approved: approved, note: controller.text.trim());
      } else {
        app.adminDecision(event, approved: approved, note: controller.text.trim());
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${event.title} — ${approved ? 'Approved' : 'Rejected'}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        final canAdviserDecide =
            app.currentRole == UserRole.adviser && event.status == EventApprovalStatus.pendingAdviser;
        final canAdminDecide =
            app.currentRole == UserRole.admin && event.status == EventApprovalStatus.pendingAdmin;

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
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _AttendanceCard(event: event),
                  if (app.currentRole != UserRole.admin) ...[
                    const SizedBox(height: 14),
                    _FeedbackCard(
                      event: event,
                      onEdit: app.currentRole == UserRole.adviser ? () => _openFeedbackDialog(context) : null,
                    ),
                  ],
                  if (app.currentRole == UserRole.officer) ...[
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