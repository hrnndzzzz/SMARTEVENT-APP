import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/app_layout.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import 'proposal_steps.dart';
import 'sap_part1_screen.dart';
import 'sap_part2_screen.dart';
import 'sap_part3_screen.dart';

/// The proposal, as the person writing it sees it.
///
/// Three steps, not six. Parts 4 to 6 belong to the SDS Office, and a
/// six-step bar would show a proposer three steps they can never
/// complete — a progress bar that cannot reach the end is worse than no
/// bar at all.
///
/// After the third the proposal leaves them: it goes to the SDS Office
/// for clearance, then to paper for signing. The waiting state says so
/// plainly rather than leaving the screen looking unfinished.
class SapProposerFlowScreen extends StatefulWidget {
  const SapProposerFlowScreen({super.key, required this.form});

  final SapForm form;

  @override
  State<SapProposerFlowScreen> createState() => _SapProposerFlowScreenState();
}

class _SapProposerFlowScreenState extends State<SapProposerFlowScreen> {
  late final SapForm _form = widget.form;

  @override
  void initState() {
    super.initState();
    _form.load().then((_) {
      if (mounted) _fillFromAccount();
    });
  }

  /// Puts the account's own organization and department on the form.
  ///
  /// Which organization an event belongs to is a fact about the account,
  /// not a choice to be made per event: a JPSSITE officer proposes for
  /// JPSSITE. So it is filled in rather than asked for, and left
  /// editable only because the name cannot always be resolved.
  ///
  /// Only Admin and Super Admin may list organizations, so for everyone
  /// else the name is blank and has to be typed. That is a gap in
  /// `/auth/me`, which returns ids without names.
  void _fillFromAccount() {
    final app = context.read<AppState>();
    final account = app.currentAccount;
    if (account == null) return;
    if ((_form.details.organizationName ?? '').isNotEmpty) return;

    final org = app.organizations
        .where((o) => o.id == account.organizationId)
        .map((o) => o.name)
        .firstOrNull;
    final department = app.departments
        .where((d) => d.id == account.departmentId)
        .map((d) => d.name)
        .firstOrNull;

    if (org == null && department == null) return;
    _form.updateDetails(
      (d) => d.copyWith(organizationName: org, department: department),
    );
  }

  /// The three parts that are the proposer's, with the part screen each
  /// one opens.
  static const List<(SapPart, String)> _steps = [
    (SapPart.one, 'Details'),
    (SapPart.two, 'Support'),
    (SapPart.three, 'Breakdown'),
  ];

  /// The step to land on: the first one that is not finished, or the
  /// last if they all are.
  int get _current {
    for (var i = 0; i < _steps.length; i++) {
      if (_form.statusOf(_steps[i].$1) != SapPartStatus.complete) return i;
    }
    return _steps.length - 1;
  }

  bool get _allDone => _steps.every(
    (s) => _form.statusOf(s.$1) == SapPartStatus.complete,
  );

  /// True once it has gone to the SDS Office and is out of the
  /// proposer's hands.
  bool get _submitted {
    final state = _form.state;
    return state != null &&
        state != SapState.draft &&
        state != SapState.revisionRequested;
  }

  /// Which semester an activity falls in, from its date.
  ///
  /// The event record wants one and the paper form has no such field,
  /// so asking for it would be asking for something the university does
  /// not. Philippine academic year: first runs August to December,
  /// second January to May, and the short summer term after that.
  static Semester _semesterOf(DateTime date) {
    if (date.month >= 8) return Semester.first;
    if (date.month <= 5) return Semester.second;
    return Semester.summer;
  }

  /// Makes the event this form belongs to, from what Part 1 says.
  ///
  /// Filling the form is how an event gets created now, so the record
  /// is a consequence of the first part rather than something asked for
  /// beforehand.
  Future<void> _createEventIfNeeded() async {
    if (_form.hasEvent) return;
    final d = _form.details;
    final title = (d.title ?? '').trim();
    if (title.isEmpty || d.activityDate == null) return;

    final app = context.read<AppState>();
    final error = await app.addEvent(
      title: title,
      estimatedCost: double.tryParse(d.totalBudget ?? '') ?? 0,
      eventDate: d.activityDate,
      description: d.rationale,
      schoolYear: d.schoolYear ?? '',
      semester: _semesterOf(d.activityDate!),
      eventScope: d.scope == 'departmental'
          ? EventScope.departmental
          : EventScope.organizational,
      submitNow: false,
    );

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final created = app.events.isNotEmpty ? app.events.first.remoteId : null;
    if (created != null) await _form.bindEvent(created);
  }

  Future<void> _open(SapPart part) async {
    final screen = switch (part) {
      SapPart.two => SapPart2Screen(form: _form),
      SapPart.three => SapPart3Screen(form: _form),
      _ => SapPart1Screen(form: _form),
    };
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (!mounted) return;
    // Coming back from Part 1 is the first moment there is enough to
    // make the event with.
    if (part == SapPart.one) await _createEventIfNeeded();
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    final ok = await _form.submit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Sent to the SDS Office.'
              : _form.error ?? 'Could not send it.',
        ),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _form,
      builder: (context, _) {
        if (_submitted) return _waiting(context);

        final current = _current;

        return BrutScreen(
          header: BrutFlowHeader(
            title: _steps[current].$1.title,
            // Named for where it sits in the whole job, not for the
            // screen it happens to be. Creating the event and filling
            // its form is one task, and calling the second half
            // something else makes it look optional.
            flowName: _form.seed == null
                ? 'Proposal form'
                : 'New event · proposal form',
            // The same five the create screen shows. The first two are
            // done as soon as the event exists, which it does by the
            // time anyone is standing here.
            currentStep: ProposalSteps.forPart(current),
            onBack: () => Navigator.of(context).maybePop(),
            steps: [
              BrutStep(label: ProposalSteps.labels[ProposalSteps.budget]),
              BrutStep(label: ProposalSteps.labels[ProposalSteps.event]),
              for (var i = 0; i < _steps.length; i++)
                BrutStep(
                  label: ProposalSteps.labels[ProposalSteps.forPart(i)],
                  // A step is reachable once the one before it has been
                  // started; jumping to the breakdown before there is an
                  // activity to budget for helps nobody.
                  onJump: i == 0 || _startedUpTo(i)
                      ? () => _open(_steps[i].$1)
                      : null,
                ),
            ],
          ),
          footer: BrutFooter(
            note: _allDone
                ? 'All three parts filled in'
                : '${_doneCount()} of 3 filled in',
            secondary: _allDone
                ? null
                : BrutButton(
                    label: 'Open ${_steps[current].$2.toLowerCase()}',
                    tone: BrutTone.neutral,
                    onPressed: () => _open(_steps[current].$1),
                  ),
            child: BrutButton(
              label: 'Send to the SDS Office',
              icon: Icons.outbox,
              busy: _form.saving,
              busyLabel: 'Sending',
              onPressed: _allDone ? _submit : null,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_form.isLocalOnly)
                const BrutInlineMessage(
                  tone: BrutTone.sun,
                  icon: Icons.cloud_off,
                  text:
                      'This backend has no proposal-form routes yet, so '
                      'everything here stays on this phone until it does.',
                ),
              // Said once, at the top, on the way in from creating the
              // event: the record exists, this is the rest of it.
              if (_form.seed != null && _doneCount() == 0) ...[
                const BrutInlineMessage(
                  tone: BrutTone.mint,
                  icon: Icons.check_circle_outline,
                  text:
                      'Event created. What you already typed is filled in '
                      'below — the rest is what the SDS Office needs.',
                ),
                const SizedBox(height: AppLayout.tight),
              ],
              if (_form.state == SapState.revisionRequested) ...[
                BrutInlineMessage(
                  tone: BrutTone.coral,
                  icon: Icons.undo,
                  text: _form.proposal?.returnRemarks?.isNotEmpty ?? false
                      ? 'Returned: ${_form.proposal!.returnRemarks}'
                      : 'Returned for revision. Make the changes and send '
                            'it again.',
                ),
                const SizedBox(height: AppLayout.tight),
              ],
              const SizedBox(height: AppLayout.tight),

              for (var i = 0; i < _steps.length; i++) ...[
                _StepRow(
                  number: i + 1,
                  title: _steps[i].$1.title,
                  status: _form.statusOf(_steps[i].$1),
                  onTap: () => _open(_steps[i].$1),
                ),
                const SizedBox(height: AppLayout.tight),
              ],

              const SizedBox(height: AppLayout.tight),
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.info_outline,
                text:
                    'Parts 4 to 6 are the SDS Office\'s: clearance, the '
                    'nine signatures, and the evaluation afterwards. You '
                    'do not fill those in.',
              ),
            ],
          ),
        );
      },
    );
  }

  int _doneCount() => _steps
      .where((s) => _form.statusOf(s.$1) == SapPartStatus.complete)
      .length;

  bool _startedUpTo(int index) {
    for (var i = 0; i < index; i++) {
      if (_form.statusOf(_steps[i].$1) == SapPartStatus.empty) return false;
    }
    return true;
  }

  /// Where the proposal has got to once it is no longer theirs.
  Widget _waiting(BuildContext context) {
    final state = _form.state;
    final (line, detail, tone) = switch (state) {
      SapState.pendingReview => (
        'With the SDS Office',
        'They check Part 4, then it is printed for the nine signatures. '
            'You will be told when it has been approved.',
        BrutTone.sun,
      ),
      SapState.approved => (
        'Approved',
        'The signed copy is on file. Nothing more to do until the '
            'activity has run.',
        BrutTone.mint,
      ),
      SapState.completed => (
        'Completed',
        'Evaluated and closed.',
        BrutTone.mint,
      ),
      _ => ('Sent', 'Waiting on the SDS Office.', BrutTone.sun),
    };

    return BrutScreen(
      header: BrutHeader(
        title: 'Proposal form',
        eyebrow: 'SAS-SDS-FO-020 (001)',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.section),
          BrutCard(
            tone: tone,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MonoLabel('Where it is'),
                const SizedBox(height: 6),
                Text(line, style: AppText.display.copyWith(fontSize: 26)),
                const SizedBox(height: 10),
                Text(detail, style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.section),
          const BrutInlineMessage(
            tone: BrutTone.neutral,
            icon: Icons.lock_outline,
            text:
                'Parts 1 to 3 are read-only while it is under review. If '
                'something has to change, the SDS Office returns it and '
                'they open again.',
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.title,
    required this.status,
    required this.onTap,
  });

  final int number;
  final String title;
  final SapPartStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      SapPartStatus.complete => ('Filled in', BrutTone.mint),
      SapPartStatus.partial => ('Started', BrutTone.sun),
      _ => ('Not started', BrutTone.neutral),
    };

    return BrutListRow(
      title: title,
      meta: 'Part $number',
      marker: SizedBox(
        width: 26,
        child: Text('$number', style: AppText.number.copyWith(fontSize: 20)),
      ),
      trailing: BrutBadge(label: label, tone: tone),
      onTap: onTap,
    );
  }
}
