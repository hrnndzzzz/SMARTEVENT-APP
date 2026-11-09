import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/app_state.dart';
import '../../state/sap_form.dart';
import '../../theme/app_layout.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import 'sap_cover_screen.dart';
import 'sap_part1_screen.dart';
import 'sap_steps_screen.dart';
import 'sap_form_screen.dart';

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
  /// A form is being loaded to open. A second tap meanwhile — the band is
  /// easy to hit twice — started a second proposal beside the first.
  static bool _starting = false;

  static Future<void> start(BuildContext context, SapForm form) async {
    if (_starting) return;
    _starting = true;
    final Widget? screen;
    try {
      screen = await _screenFor(context, form);
    } finally {
      // Released before the push: a route's future only completes when it
      // is popped, and one never popped would block proposing for good.
      _starting = false;
    }
    if (screen == null || !context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen!));
  }

  /// The screen [start] opens, or null when there is none to open.
  static Future<Widget?> _screenFor(BuildContext context, SapForm form) async {
    final app = _appOf(context);

    // A proposer the server will refuse should hear it before filling in
    // three steps, not after: without an assignment there is no
    // organization for the event to belong to.
    if (!form.hasEvent && (app?.lacksProposerAssignment ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'An administrator must assign your department and '
            'organization before you can propose an event.',
          ),
        ),
      );
      return null;
    }
    final choosesScope = !form.hasEvent && (app?.choosesEventScope ?? false);
    if (choosesScope) await app!.loadScopeOptions();
    if (!context.mounted) return null;

    await form.load();
    if (!context.mounted) return null;

    if (form.isReadOnly) return SapFormScreen(form: form);

    fillFromAccount(context, form);

    // Already sent, or decided: there is nothing to fill in, so say where
    // it has got to instead of opening a form nobody may edit.
    if (!form.canEditProposerParts) return SapProposalStatus(form: form);

    // The cover comes first: the header the paper opens with, the two
    // dates filled in, and the on-or-off-campus question that decides
    // what the rest of the form will ask for.
    form.updateDetails(
      (d) => d.copyWith(
        schoolYear: d.schoolYear?.isNotEmpty == true
            ? d.schoolYear
            : SapCoverScreen.schoolYearFor(DateTime.now()),
        proposalDate: d.proposalDate ?? DateTime.now(),
        departmentType: d.departmentType?.isNotEmpty == true
            ? d.departmentType
            : SapPart1Screen.departmentTypes.first,
      ),
    );

    return SapCoverScreen(
      form: form,
      onBegin: (coverContext) => _openSteps(coverContext, form),
      departments: choosesScope ? app!.departments : null,
      organizationsIn: choosesScope ? app!.organizationsIn : null,
    );
  }

  /// "Go back" from a run whose event this visit made: the event goes
  /// too, as the dialog promised. A draft that was opened to carry on is
  /// never touched.
  static Future<void> discardMadeEvent(
    BuildContext context,
    SapForm form,
  ) async {
    final id = form.eventId;
    final app = _appOf(context);
    if (!form.madeEvent || id == null || app == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final error = await app.deleteDraftEvent(id);
    if (error == null) {
      form.unbindEvent();
    } else {
      // Kept, then, and said so: it is still under Events to delete.
      messenger.showSnackBar(
        SnackBar(content: Text('The draft was kept. $error')),
      );
    }
  }

  static Future<void> _openSteps(BuildContext context, SapForm form) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SapStepsScreen(
          form: form,
          onCreateEvent: (partContext) =>
              _createEventIfNeeded(partContext, form),
          onSubmit: (partContext) async {
            final ok = await form.submit();
            if (!partContext.mounted) return;

            if (!ok) {
              ScaffoldMessenger.of(partContext).showSnackBar(
                SnackBar(content: Text(form.error ?? 'Could not send it.')),
              );
              return;
            }

            // Out of the three parts entirely: they are not editable
            // now, so leaving them to go back into would be offering
            // something that no longer works.
            Navigator.of(partContext).popUntil((route) => route.isFirst);
            if (partContext.mounted) {
              ScaffoldMessenger.of(partContext).showSnackBar(
                const SnackBar(content: Text('Sent for department review.')),
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
  static Future<bool> _createEventIfNeeded(
    BuildContext context,
    SapForm form,
  ) async {
    if (form.hasEvent) return true;
    final d = form.details;
    final title = (d.title ?? '').trim();
    if (title.isEmpty || d.activityDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Give the activity a title and a date first.'),
        ),
      );
      return false;
    }

    final app = context.read<AppState>();

    // The same activity already drafted by this proposer — left on the
    // server when the app was closed mid-form — is carried on rather than
    // made a second time under the same title.
    final me = app.currentAccount?.id;
    final drafted = app.events
        .where(
          (e) =>
              me != null &&
              e.proposedBy == me &&
              e.status == EventApprovalStatus.draft &&
              e.remoteId != null &&
              e.title.trim().toLowerCase() == title.toLowerCase(),
        )
        .firstOrNull;
    if (drafted != null) {
      await form.bindEvent(drafted.remoteId!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Carrying on your draft "${drafted.title}".')),
        );
      }
      return true;
    }

    String? created;
    final error = await app.addEvent(
      onCreated: (id) => created = id,
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
      // Null for every proposer but a Super Admin, whose own assignment
      // the server applies.
      departmentId: form.scopeDepartmentId,
      organizationId: form.scopeOrganizationId,
    );

    if (!context.mounted) return false;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return false;
    }

    final id = created;
    if (id == null) return false;
    await form.bindEvent(id, made: true);
    return true;
  }

  static AppState? _appOf(BuildContext context) {
    try {
      return context.read<AppState>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Whether the signed-in account is the SDS Office, whose Part 4 and
  /// review actions those are. False with no [AppState] to ask: nobody is
  /// taken for the office on a hunch, and the server refuses anyone else
  /// whatever the screen offers.
  static bool isSdsStaff(BuildContext context) =>
      _appOf(context)?.currentRole == UserRole.sdsStaff;

  /// Puts the account's own organization and department on the form.
  ///
  /// Which organization an event belongs to is a fact about the account,
  /// not a choice per event: a JPSSITE officer proposes for JPSSITE.
  ///
  /// The organization comes from `/auth/me`, which has named it since
  /// 24 Oct — so this now works for the student officers who actually
  /// fill the form, not only for the Admins who may list organizations.
  ///
  /// The department is named there too since 29 Oct; an older backend
  /// leaves it to the list, and Part 1 asks for it when neither names it.
  /// Each is filled whenever it is still blank — a draft saved before then
  /// may hold the organization and not the department.
  static void fillFromAccount(BuildContext context, SapForm form) {
    final AppState app;
    try {
      app = context.read<AppState>();
    } on ProviderNotFoundException {
      return;
    }

    final account = app.currentAccount;
    if (account == null) return;

    // The account's own names first; the lists are only a fallback for an
    // older backend that sends the ids alone.
    final org = (account.organizationName?.isNotEmpty ?? false)
        ? account.organizationName
        : app.organizations
              .where((o) => o.id == account.organizationId)
              .map((o) => o.name)
              .firstOrNull;
    final department = (account.departmentName?.isNotEmpty ?? false)
        ? account.departmentName
        : app.departments
              .where((d) => d.id == account.departmentId)
              .map((d) => d.name)
              .firstOrNull;

    if (org == null && department == null) return;
    form.updateDetails(
      (d) => d.copyWith(
        organizationName: (d.organizationName ?? '').isEmpty ? org : null,
        department: (d.department ?? '').isEmpty ? department : null,
      ),
    );
  }
}

/// Where a proposal has got to, once it is no longer the proposer's.
class SapProposalStatus extends StatelessWidget {
  const SapProposalStatus({super.key, required this.form});

  final SapForm form;

  /// Whose words the remark is, when the server says; an older one does
  /// not. Read only for a returned proposal, which is the only time
  /// [SapForm.returnedBy] means anything.
  String get _returned {
    final who = form.returnedBy;
    final said = form.returnRemarks ?? 'Edit the parts and send it again.';
    return who == null ? said : 'Returned by ${who.label}: $said';
  }

  @override
  Widget build(BuildContext context) {
    final (line, detail, tone) = switch (form.state) {
      // The Moderator and Dean come before the SDS Office. Without this
      // it fell through to "Waiting on the SDS Office", which is not yet
      // true of it.
      SapState.pendingDepartmentReview => (
        'With the Moderator and Dean',
        'They approve it before it goes to the SDS Office. If one of them '
            'returns it, it opens for you again with their remarks.',
        BrutTone.sun,
      ),
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
      SapState.revisionRequested => ('Returned', _returned, BrutTone.coral),
      SapState.rejected => (
        'Rejected',
        [
          'The SDS Office rejected this proposal. It is final; start a new '
              'one to try again.',
          ...form.sdsRemarkLines(overall: true),
        ].join('\n'),
        BrutTone.coral,
      ),
      // A load that failed, or has not finished, leaves no state to read.
      // That is not a proposal the office has, so it must not say so.
      null => (
        'Not loaded',
        form.error ??
            'The proposal could not be loaded. Open it again to retry.',
        BrutTone.neutral,
      ),
      _ => ('Sent', 'Waiting on the SDS Office.', BrutTone.sun),
    };

    // Open to the proposer again, or closed for good: "read-only while it
    // is under review" is neither, so it says nothing then. Nor does it
    // for a proposal that never loaded, which is not under review at all.
    final lock = switch (form.state) {
      null || SapState.revisionRequested || SapState.rejected => null,
      SapState.pendingDepartmentReview =>
        'Parts 1 to 3 are read-only while it is under review. If '
            'something has to change, the Moderator or Dean returns it and '
            'they open again.',
      // Signed, the revision stays as it is; "under review" and a return
      // are no longer what happens to it.
      SapState.sdsSigned || SapState.approved || SapState.completed =>
        'Parts 1 to 3 are locked: the SDS Office has signed this revision.',
      _ =>
        'Parts 1 to 3 are read-only while it is under review. If '
            'something has to change, the SDS Office returns it and '
            'they open again.',
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
          if (lock != null)
            BrutInlineMessage(
              tone: BrutTone.neutral,
              icon: Icons.lock_outline,
              text: lock,
            ),
        ],
      ),
    );
  }
}
