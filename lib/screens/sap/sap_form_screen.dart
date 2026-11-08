import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/export_saver.dart';
import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import '../../widgets/last_change_note.dart';
import 'sap_attachment_rows.dart';
import 'sap_part1_screen.dart';
import 'sap_part2_screen.dart';
import 'sap_part3_screen.dart';
import 'sap_part4_screen.dart';
import 'sap_part5_screen.dart';
import 'sds_sign_screen.dart';
import 'sap_part6_screen.dart';
import 'sap_proposal_flow.dart';

/// The proposal form, as six parts.
///
/// The paper form is one six-page document and people fill it in a part
/// at a time, so this is a list of those parts rather than a single long
/// scroll. Each row says how far along it is and who it belongs to —
/// Parts 4 to 6 are the SDS Office's, which the paper marks in red.
class SapFormScreen extends StatefulWidget {
  const SapFormScreen({super.key, required this.form});

  final SapForm form;

  @override
  State<SapFormScreen> createState() => _SapFormScreenState();
}

class _SapFormScreenState extends State<SapFormScreen> {
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    // After the load, which replaces the details: a draft opened from the
    // event needs the account's organization and department as much as a
    // new one does, and Part 1 has no field for the department.
    widget.form.load().then((_) {
      if (mounted) SapProposalFlow.fillFromAccount(context, widget.form);
    });
    widget.form.loadAttachments();
  }

  /// A PDF that goes with the proposal to its reviewers and the SDS
  /// Office. Only while the proposer can still edit, as the server allows.
  Future<void> _attachSupportingPdf() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose a supporting PDF',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final file = picked.firstOrNull;
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final problem = await widget.form.attachFile(
      category: SapAttachmentCategory.other,
      bytes: bytes,
      filename: file.name,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(problem ?? '${file.name} attached.')),
    );
  }

  /// The SDS Office's remarks print as comments only if the proposer says
  /// so; with none saved there is nothing to ask. Null means cancelled.
  Future<bool?> _askWithComments() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Print the form'),
        content: const Text(
          "With comments: the form with the SDS Office's remarks beside "
          'each part.\n\n'
          'Without comments: the clean form, as it goes to the signatories.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Print without comments'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Print with comments'),
          ),
        ],
      ),
    );
  }

  Future<void> _print(SapForm form) async {
    final withComments = form.hasSdsRemarks ? await _askWithComments() : false;
    if (withComments == null || !mounted) return;
    setState(() => _printing = true);
    final file = await form.printableForm(withComments: withComments);
    if (!mounted) return;
    setState(() => _printing = false);

    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(form.error ?? 'Nothing to print yet.')),
      );
      return;
    }
    await ExportSaver.share(file, subject: 'SAS-SDS-FO-020 proposal form');
  }

  Future<void> _open(SapPart part) async {
    final form = widget.form;
    // Opened while offline, say: load it now rather than open a part on a
    // form that holds none of the proposal.
    if (form.hasEvent && form.proposal == null && !form.isLocalOnly) {
      await form.load();
      if (!mounted) return;
      SapProposalFlow.fillFromAccount(context, form);
    }
    final screen = switch (part) {
      SapPart.one => SapPart1Screen(form: form),
      SapPart.two => SapPart2Screen(form: form),
      SapPart.three => SapPart3Screen(form: form),
      SapPart.four => SapPart4Screen(form: form),
      SapPart.five => SapPart5Screen(form: form),
      SapPart.six => SapPart6Screen(form: form),
    };
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SapForm>.value(
      value: widget.form,
      child: Consumer<SapForm>(
        builder: (context, form, _) {
          final isSds = SapProposalFlow.isSdsStaff(context);
          return BrutScreen(
            header: BrutHeader(
              title: 'Proposal form',
              // The revision belongs beside the form's own number: a
              // second submission is a different piece of paper to the
              // office, and nothing said which one this was.
              eyebrow: form.isResubmission
                  ? 'SAS-SDS-FO-020 (001) · REVISION ${form.revisionNo}'
                  : 'SAS-SDS-FO-020 (001)',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            footer: BrutFooter(
              note: '${form.completedParts} of 6 parts filled in',
              child: BrutButton(
                label: 'Submit for review',
                icon: Icons.outbox,
                busy: form.saving,
                busyLabel: 'Submitting',
                onPressed: form.canEditProposerParts
                    ? () => _submit(form)
                    : null,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (form.loading) ...[
                  const SizedBox(height: 40),
                  const Center(child: BrutSpinner()),
                  const SizedBox(height: 40),
                ] else ...[
                  // Who has the proposal, before the six parts. Sending it
                  // goes to the Moderator and the Dean first, and the
                  // proposal used to read as nothing in particular while
                  // they had it.
                  if (form.state == SapState.pendingDepartmentReview)
                    const BrutInlineMessage(
                      tone: BrutTone.sun,
                      icon: Icons.hourglass_top,
                      text:
                          'With the Moderator and Dean. They approve it '
                          'before it goes to the SDS Office.',
                    ),
                  // What to change, before the six parts it applies to.
                  // A returned proposal used to come back with the state
                  // alone and no reason, so the proposer had to guess —
                  // the server has carried these words all along.
                  if (form.wasReturned)
                    BrutInlineMessage(
                      tone: BrutTone.coral,
                      icon: Icons.assignment_return_outlined,
                      text: _returnedText(form),
                    ),
                  // Final: nothing follows it and nothing can be sent
                  // again, so it says so rather than reading as a return.
                  // The office made the decision, so it is not advised to
                  // start a new proposal.
                  if (form.state == SapState.rejected)
                    BrutInlineMessage(
                      tone: BrutTone.coral,
                      icon: Icons.block,
                      text: [
                        isSds
                            ? 'Rejected by the SDS Office. This proposal is '
                                  'final.'
                            : 'Rejected by the SDS Office. This proposal is '
                                  'final; start a new one to try again.',
                        ...form.sdsRemarkLines(overall: true),
                      ].join('\n'),
                    ),
                  // The activity has run and Part 6 is the office's to
                  // fill in. Without this the form simply ended, locked,
                  // with nothing saying who was being waited on.
                  if (form.awaitingEvaluation)
                    BrutInlineMessage(
                      tone: BrutTone.sun,
                      icon: Icons.hourglass_top,
                      text: isSds
                          ? 'The activity has run. Record how it went in '
                                'Part 6.'
                          : 'Waiting on the SDS Office to record how this '
                                'went. Part 6 is theirs to fill in; nothing '
                                'more is needed from you.',
                    ),
                  if (form.isLocalOnly)
                    BrutInlineMessage(
                      tone: BrutTone.sun,
                      icon: Icons.cloud_off,
                      // Two different causes, and guessing the wrong one
                      // is how a message stops being believed: the demo
                      // has no server at all, while a running backend
                      // refusing this proposal is about this event.
                      text: form.isDemo
                          ? 'Demo mode: nothing here leaves the phone.'
                          : 'This event has no proposal on the server, so '
                                'everything here stays on this phone.',
                    ),
                  if (form.isStale)
                    const BrutInlineMessage(
                      tone: BrutTone.coral,
                      icon: Icons.sync_problem,
                      text:
                          'Someone else changed this proposal. Reopen it to '
                          'see their version before saving again.',
                    ),
                  if (form.error case final message?)
                    BrutInlineMessage(
                      tone: BrutTone.coral,
                      icon: Icons.error_outline,
                      text: message,
                    ),
                  if (form.eventId case final eventId?) ...[
                    const SizedBox(height: 10),
                    LastChangeNote(area: 'proposals', entityId: eventId),
                  ],
                  const SizedBox(height: 14),
                  SapAttachmentRows(form: form),
                  // Before it is sent: once submitted, the server takes no
                  // more files until the proposal comes back for changes.
                  if (form.canEditProposerParts && !form.isLocalOnly) ...[
                    BrutButton(
                      label: 'Attach a supporting PDF',
                      icon: Icons.picture_as_pdf_outlined,
                      tone: BrutTone.neutral,
                      busy: form.saving,
                      busyLabel: 'Attaching',
                      onPressed: _attachSupportingPdf,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'PDF, up to 10 MB. Reviewers and the SDS Office see it '
                      'with the proposal.',
                      style: AppText.caption,
                    ),
                    const SizedBox(height: 14),
                  ],
                  for (final part in SapPart.values) ...[
                    _PartRow(
                      part: part,
                      status: form.statusOf(part),
                      onTap: () => _open(part),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 10),
                  BrutButton(
                    label: 'Print or share the form',
                    icon: Icons.print_outlined,
                    tone: BrutTone.neutral,
                    busy: _printing,
                    busyLabel: 'Preparing',
                    onPressed: form.isLocalOnly ? null : () => _print(form),
                  ),
                  const SizedBox(height: 10),
                  BrutInlineMessage(
                    tone: BrutTone.neutral,
                    icon: Icons.info_outline,
                    // What comes back depends on the revision: a working
                    // copy while it is still being filled in, and the
                    // stored signed form once the SDS Office has signed
                    // it. The nine on paper print empty either way.
                    text: switch (form.state) {
                      SapState.sdsSigned ||
                      SapState.approved ||
                      SapState.completed =>
                        'This is the signed form the SDS Office stored, '
                            'watermarked by the server. The nine signature '
                            'slots print empty, to be signed by hand.',
                      // The server marks it, as it marks the signed one.
                      SapState.rejected =>
                        'This copy prints with the SDS Office\'s rejection '
                            'mark, added by the server.',
                      _ =>
                        'The printed copy uses the university\'s own '
                            'six-page layout, produced by the server so the '
                            'paper always matches the record. The nine '
                            'signature slots print empty, to be signed by '
                            'hand.',
                    },
                  ),
                  // The office's own actions: the server takes them from
                  // SDS staff alone, so nobody else is offered them.
                  if (form.state == SapState.pendingReview && isSds) ...[
                    const SizedBox(height: 18),
                    const BrutSectionTitle('SDS Office'),
                    const SizedBox(height: 8),
                    BrutButton(
                      label: 'Review and decide',
                      icon: Icons.draw_outlined,
                      onPressed: form.isReadOnly
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SdsSignScreen(form: form),
                              ),
                            ),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _submit(SapForm form) async {
    final ok = await form.submit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Sent for department review.'
              : form.error ?? 'Could not submit.',
        ),
      ),
    );
  }

  /// Whose words these are. An older server and the demo do not say who
  /// returned it, and before the department could send a proposal back
  /// only the SDS Office did, so that is what the old wording stays for.
  String _returnedText(SapForm form) {
    final who = form.returnedBy;
    final said = form.returnRemarks;
    if (who == null) {
      return said == null
          ? 'The SDS Office sent this back for changes. '
                'Edit the parts below and submit it again.'
          : 'The SDS Office sent this back: $said';
    }
    return [
      said == null
          ? 'Returned by ${who.label}. '
                'Edit the parts below and submit it again.'
          : 'Returned by ${who.label}: $said',
      // Pinned to a section of the form, so they are the office's own and
      // not something to put under the Moderator's or the Dean's name.
      if (who == SapReturnedBy.sds) ...form.sdsRemarkLines(),
    ].join('\n');
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({
    required this.part,
    required this.status,
    required this.onTap,
  });

  final SapPart part;
  final SapPartStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      SapPartStatus.complete => ('Filled in', BrutTone.mint),
      SapPartStatus.partial => ('Started', BrutTone.sun),
      SapPartStatus.empty => ('Not started', BrutTone.neutral),
      SapPartStatus.locked => ('Not yet', BrutTone.neutral),
    };

    return BrutListRow(
      title: part.title,
      meta: part.isSdsOnly
          ? 'Part ${part.number} · SDS Office'
          : 'Part ${part.number}',
      marker: SizedBox(
        width: 26,
        child: Text(
          '${part.number}',
          style: AppText.number.copyWith(fontSize: 20),
        ),
      ),
      trailing: BrutBadge(label: label, tone: tone),
      onTap: status == SapPartStatus.locked ? null : onTap,
    );
  }
}
