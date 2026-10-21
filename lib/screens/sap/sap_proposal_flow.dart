import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/app_state.dart';
import '../../state/sap_form.dart';
import '../../theme/app_layout.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import 'sap_part1_screen.dart';
import 'sap_part2_screen.dart';
import 'sap_part3_screen.dart';

/// Filling in a proposal, one part after another.
///
/// Not a menu of three parts to choose between: Part 1 is the first
/// screen, Part 2 the second, Part 3 the third. A list that sends you
/// into a form and back out again makes three forms feel like three
/// errands.
///
/// Creating an event is this flow. The event record is made on the way
/// out of Part 1, from what Part 1 says, so nothing exists until there
/// is a title and a date for it.
abstract final class SapProposalFlow {
  static Future<void> start(BuildContext context, SapForm form) async {
    await form.load();
    if (!context.mounted) return;

    _fillFromAccount(context, form);

    // Already with the SDS Office: there is nothing to fill in, so say
    // where it has got to instead of opening a form nobody may edit.
    if (!form.canEditProposerParts) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SapProposalStatus(form: form)),
      );
      return;
    }

    await _openPart1(context, form);
  }

  static Future<void> _openPart1(BuildContext context, SapForm form) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SapPart1Screen(
          form: form,
          step: 0,
          onContinue: (partContext) async {
            await _createEventIfNeeded(partContext, form);
            if (!partContext.mounted) return;
            await _openPart2(partContext, form);
          },
        ),
      ),
    );
  }

  static Future<void> _openPart2(BuildContext context, SapForm form) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SapPart2Screen(
          form: form,
          step: 1,
          onContinue: (partContext) => _openPart3(partContext, form),
        ),
      ),
    );
  }

  static Future<void> _openPart3(BuildContext context, SapForm form) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SapPart3Screen(
          form: form,
          step: 2,
          onContinue: (partContext) async {
            final ok = await form.submit();
            if (!partContext.mounted) return;

            if (!ok) {
              ScaffoldMessenger.of(partContext).showSnackBar(
                SnackBar(
                  content: Text(form.error ?? 'Could not send it.'),
                ),
              );
              return;
            }

            // Out of the three parts entirely: they are not editable
            // now, so leaving them on the stack to go back into would
            // be offering something that no longer works.
            Navigator.of(partContext).popUntil((route) => route.isFirst);
            if (partContext.mounted) {
              ScaffoldMessenger.of(partContext).showSnackBar(
                const SnackBar(content: Text('Sent to the SDS Office.')),
              );
            }
          },
        ),
      ),
    );
  }

  /// Which semester an activity falls in, from its date.
  ///
  /// The event record wants one and the paper form has no such field,
  /// so asking would be asking for something the university does not.
  /// Philippine academic year: first runs August to December, second
  /// January to May, and the short summer term after that.
  static Semester semesterOf(DateTime date) {
    if (date.month >= 8) return Semester.first;
    if (date.month <= 5) return Semester.second;
    return Semester.summer;
  }

  /// Makes the event this proposal belongs to, from what Part 1 says.
  static Future<void> _createEventIfNeeded(
    BuildContext context,
    SapForm form,
  ) async {
    if (form.hasEvent) return;
    final d = form.details;
    final title = (d.title ?? '').trim();
    if (title.isEmpty || d.activityDate == null) return;

    final app = context.read<AppState>();
    final error = await app.addEvent(
      title: title,
      estimatedCost: double.tryParse(d.totalBudget ?? '') ?? 0,
      eventDate: d.activityDate,
      description: d.rationale,
      schoolYear: d.schoolYear ?? '',
      semester: semesterOf(d.activityDate!),
      eventScope: d.scope == 'departmental'
          ? EventScope.departmental
          : EventScope.organizational,
      submitNow: false,
    );

    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final created = app.events.isNotEmpty ? app.events.first.remoteId : null;
    if (created != null) await form.bindEvent(created);
  }

  /// Puts the account's own organization and department on the form.
  ///
  /// Which organization an event belongs to is a fact about the account,
  /// not a choice per event: a JPSSITE officer proposes for JPSSITE.
  ///
  /// Only Admin and Super Admin may list organizations, so for everyone
  /// else the name cannot be resolved and the field stays typed. That is
  /// a gap in `/auth/me`, which returns ids without names.
  static void _fillFromAccount(BuildContext context, SapForm form) {
    final AppState app;
    try {
      app = context.read<AppState>();
    } on ProviderNotFoundException {
      return;
    }

    final account = app.currentAccount;
    if (account == null) return;
    if ((form.details.organizationName ?? '').isNotEmpty) return;

    final org = app.organizations
        .where((o) => o.id == account.organizationId)
        .map((o) => o.name)
        .firstOrNull;
    final department = app.departments
        .where((d) => d.id == account.departmentId)
        .map((d) => d.name)
        .firstOrNull;

    if (org == null && department == null) return;
    form.updateDetails(
      (d) => d.copyWith(organizationName: org, department: department),
    );
  }
}

/// Where a proposal has got to, once it is no longer the proposer's.
class SapProposalStatus extends StatelessWidget {
  const SapProposalStatus({super.key, required this.form});

  final SapForm form;

  @override
  Widget build(BuildContext context) {
    final (line, detail, tone) = switch (form.state) {
      SapState.pendingReview => (
        'With the SDS Office',
        'They check Part 4, then it is printed for the nine signatures. '
            'You will be told when it has been approved.',
        BrutTone.sun,
      ),
      SapState.sdsSigned => (
        'Signed by the SDS Office',
        'The form is locked and printed. It is going round for the nine '
            'physical signatures.',
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
