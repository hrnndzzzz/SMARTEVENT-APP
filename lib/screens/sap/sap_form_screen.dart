import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/export_saver.dart';
import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import 'sap_part1_screen.dart';
import 'sap_part2_screen.dart';
import 'sap_part3_screen.dart';
import 'sap_part4_screen.dart';
import 'sap_part5_screen.dart';
import 'sds_sign_screen.dart';
import 'sap_part6_screen.dart';

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
    widget.form.load();
    widget.form.loadAttachments();
  }

  Future<void> _print(SapForm form) async {
    setState(() => _printing = true);
    final file = await form.printableForm();
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

  Future<void> _return(SapForm form) async {
    final remarks = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ReturnSheet(),
    );
    if (remarks == null) return;

    final ok = await form.returnForRevision(remarks);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Returned. Resubmitting creates a new revision; the '
                    'signatures already collected do not carry over.'
              : form.error ?? 'Could not return it.',
        ),
      ),
    );
  }

  Future<void> _open(SapPart part) async {
    final form = widget.form;
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
          return BrutScreen(
            header: BrutHeader(
              title: 'Proposal form',
              eyebrow: 'SAS-SDS-FO-020 (001)',
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
                  const SizedBox(height: 14),
                  // One row per file, named. Every attachment used to
                  // read "Open supporting file", so three of them gave
                  // three identical buttons and no way to tell the
                  // ROC/COC from an appendix — and a flat Material
                  // button sat oddly among the bordered rows below it.
                  for (final attachment in form.attachments) ...[
                    BrutListRow(
                      title: attachment.category?.label ?? 'Supporting file',
                      meta: attachment.filename,
                      marker: const BrutIconTile(
                        size: 32,
                        icon: Icons.attach_file,
                        tone: BrutTone.brand,
                      ),
                      onTap: () async {
                        try {
                          await ExportSaver.share(
                            await form.attachmentFile(attachment.id),
                            subject: 'Proposal attachment',
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$error')));
                        }
                      },
                    ),
                    const SizedBox(height: 10),
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
                    text:
                        form.state == SapState.sdsSigned ||
                            form.state == SapState.approved ||
                            form.state == SapState.completed
                        ? 'This is the signed form the SDS Office stored, '
                              'watermarked by the server. The nine signature '
                              'slots print empty, to be signed by hand.'
                        : 'The printed copy uses the university\'s own '
                              'six-page layout, produced by the server so the '
                              'paper always matches the record. The nine '
                              'signature slots print empty, to be signed by '
                              'hand.',
                  ),
                  if (form.state == SapState.pendingReview) ...[
                    const SizedBox(height: 18),
                    const BrutSectionTitle('SDS Office'),
                    const SizedBox(height: 8),
                    BrutButton(
                      label: 'Review and sign',
                      icon: Icons.draw_outlined,
                      onPressed: form.isReadOnly
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SdsSignScreen(form: form),
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                    BrutButton(
                      label: 'Return for revision',
                      icon: Icons.undo,
                      tone: BrutTone.coral,
                      onPressed: form.isReadOnly ? null : () => _return(form),
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
              ? 'Submitted. Print it and collect the nine signatures.'
              : form.error ?? 'Could not submit.',
        ),
      ),
    );
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

/// Why the proposal is going back. The server requires a comment, and a
/// blank one helps nobody reading it later.
class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet();

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  final _remarks = TextEditingController();

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrutSectionTitle('Return for revision'),
          const SizedBox(height: 8),
          const BrutInlineMessage(
            tone: BrutTone.sun,
            icon: Icons.warning_amber_outlined,
            text:
                'Resubmitting makes a new revision. The signatures already '
                'collected stay with the old one and have to be gathered '
                'again on the reprinted form.',
          ),
          const SizedBox(height: 12),
          BrutTextField(
            controller: _remarks,
            label: 'What needs changing',
            hint: 'Move the activity to the afternoon; morning classes clash.',
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          BrutButton(
            label: 'Send it back',
            tone: BrutTone.coral,
            onPressed: _remarks.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_remarks.text.trim()),
          ),
        ],
      ),
    );
  }
}
