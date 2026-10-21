import 'package:file_picker/file_picker.dart';
import '../../api/export_saver.dart';
import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import 'sap_form_fields.dart';

/// Part 5 — University Clearance.
///
/// Nine physical signatures, collected on paper. Nothing here signs
/// anything: the SDS Office records that it inspected a signed page, and
/// the authoritative evidence is the scan uploaded afterwards. The
/// wording is deliberate about that throughout — calling a recorded
/// checkpoint a signature would misstate what the system knows.
///
/// Before the first submission no slots exist, so the screen shows the
/// nine as the blank form has them.
class SapPart5Screen extends StatefulWidget {
  const SapPart5Screen({super.key, required this.form});

  final SapForm form;

  /// The nine slots in the order the paper prints them, used before
  /// submission. Afterwards the server's own rows replace these and
  /// carry the real position names.
  static const List<(int, String, String)> blankSlots = [
    (1, 'Organization President', 'Prepared by'),
    (2, 'Organization Moderator', 'Reviewed by'),
    (3, 'Organization Moderator', 'Reviewed by'),
    (4, 'College Dean', 'Reviewed by'),
    (5, 'SDS Coordinator / Activity Officer', 'Reviewed by'),
    (6, 'SAS Director', 'Noted by'),
    (7, 'Assistant VPAA', 'Endorsed by'),
    (8, 'VPAA', 'Recommending Approval'),
    (9, 'University President', 'Approved by'),
  ];

  @override
  State<SapPart5Screen> createState() => _SapPart5ScreenState();
}

class _SapPart5ScreenState extends State<SapPart5Screen> {
  bool _printing = false;

  late final SapForm _form = widget.form;

  @override
  void initState() {
    super.initState();
    _form.loadWorkflow();
  }

  Future<void> _record(SapWorkflowStep step) async {
    final workflow = _form.workflow;
    final evidence = await showModalBottomSheet<SapCheckpointEvidence>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecordSheet(
        step: step,
        // Every slot needs a distinct signer, so what is already
        // recorded is needed to say so before the server does.
        taken: [
          for (final s in workflow?.steps ?? const <SapWorkflowStep>[])
            ?s.evidence,
        ],
      ),
    );
    if (evidence == null) return;

    final ok = await _form.recordCheckpoint(
      stepId: step.id,
      evidence: evidence,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_form.error ?? 'Could not record it.')),
      );
    }
  }

  /// Fetches the printable form and hands it to the share sheet.
  ///
  /// Once the SDS Office has signed, this is their signed copy rather
  /// than a working one: the server stores it and watermarks it. The
  /// nine on paper print empty either way, which is the point of
  /// printing it here.
  Future<void> _printForSignatories() async {
    setState(() => _printing = true);
    final file = await _form.printableForm();
    if (!mounted) return;
    setState(() => _printing = false);

    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_form.error ?? 'Nothing to print yet.')),
      );
      return;
    }
    await ExportSaver.share(file, subject: 'SAS-SDS-FO-020 proposal form');
  }

  /// Picks the scan and sends it.
  ///
  /// The server is strict here — six unencrypted pages, flattened, under
  /// 10 MB — and it is write-once, so this confirms first rather than
  /// letting a stray tap settle an approval.
  Future<void> _uploadScan() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose the signed scan',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final file = picked.firstOrNull;
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upload this as the approval evidence?'),
        content: Text(
          '${file.name}\n\nThis approves the proposal and cannot be '
          'replaced afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await _form.uploadFinalScan(bytes: bytes, filename: file.name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Approved. The scan is stored as the signature evidence.'
              : _form.error ?? 'Could not upload it.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _form,
      builder: (context, _) {
        final workflow = _form.workflow;
        final live = workflow?.hasStarted ?? false;

        return BrutScreen(
          header: BrutHeader(
            title: 'University Clearance',
            eyebrow: 'Part 5',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SapSdsOnlyNotice(),
              const SizedBox(height: 12),
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.draw_outlined,
                text:
                    'These are signed on paper. The SDS Office records that '
                    'it has seen each signed page; the signed scan is the '
                    'evidence, not this list.',
              ),
              const SizedBox(height: 12),

              // The paper starts here, so the paper is printed from here
              // rather than from the hub two screens back.
              BrutButton(
                label: 'Print for the signatories',
                icon: Icons.print_outlined,
                tone: _form.state == SapState.sdsSigned
                    ? BrutTone.brand
                    : BrutTone.neutral,
                busy: _printing,
                busyLabel: 'Preparing',
                onPressed: _form.isLocalOnly ? null : _printForSignatories,
              ),
              if (_form.isLocalOnly) ...[
                const SizedBox(height: 8),
                const BrutInlineMessage(
                  tone: BrutTone.neutral,
                  icon: Icons.cloud_off,
                  text:
                      'The server produces the printed form, so there is '
                      'nothing to print while this proposal is only on the '
                      'phone.',
                ),
              ],
              if (_form.state == SapState.sdsSigned) ...[
                const SizedBox(height: 8),
                const BrutInlineMessage(
                  tone: BrutTone.mint,
                  icon: Icons.verified_outlined,
                  text:
                      'The SDS Office has signed. This prints their signed '
                      'copy, for the nine to sign by hand.',
                ),
              ],
              const SizedBox(height: 16),

              if (!live) ...[
                const BrutInlineMessage(
                  tone: BrutTone.sun,
                  icon: Icons.lock_clock,
                  text:
                      'The nine slots open once the proposal is submitted. '
                      'Until then this is how the printed page will look.',
                ),
                const SizedBox(height: 14),
                for (final (slot, position, label)
                    in SapPart5Screen.blankSlots) ...[
                  _SlotCard(
                    slot: slot,
                    position: position,
                    displayLabel: label,
                  ),
                  const SizedBox(height: 8),
                ],
              ] else ...[
                BrutInlineMessage(
                  tone: BrutTone.neutral,
                  icon: Icons.task_alt,
                  text:
                      '${workflow!.completedCount} of ${workflow.totalCount} '
                      'recorded on revision ${workflow.revisionNo}.',
                ),
                const SizedBox(height: 14),
                for (final step in workflow.steps) ...[
                  _SlotCard(
                    slot: step.slot,
                    position: step.position,
                    displayLabel: step.displayLabel,
                    recorded: step.isRecorded,
                    signerName: step.evidence?.signerName,
                    onRecord: step.actionable ? () => _record(step) : null,
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 6),
                const BrutInlineMessage(
                  tone: BrutTone.neutral,
                  icon: Icons.info_outline,
                  text:
                      'Slots 2 and 3 can be recorded in either order. The '
                      'rest follow the page, each after the one above it. A '
                      'checkpoint recorded wrongly is not overwritten: return '
                      'the proposal and start a fresh revision.',
                ),
                const SizedBox(height: 22),

                const BrutSectionTitle('Signed scan'),
                const SizedBox(height: 8),
                BrutInlineMessage(
                  tone: workflow.completedCount == workflow.totalCount
                      ? BrutTone.neutral
                      : BrutTone.sun,
                  icon: Icons.upload_file,
                  text: workflow.completedCount == workflow.totalCount
                      ? 'Upload the scanned, signed form. It must be a '
                            'flattened PDF of exactly six pages, no larger '
                            'than 10 MB. This is the evidence of approval, '
                            'and it cannot be replaced once sent.'
                      : 'All nine checkpoints have to be recorded before the '
                            'signed scan can be uploaded.',
                ),
                const SizedBox(height: 10),
                BrutButton(
                  label: 'Upload the signed scan',
                  icon: Icons.picture_as_pdf_outlined,
                  busy: _form.saving,
                  busyLabel: 'Uploading',
                  onPressed:
                      workflow.completedCount == workflow.totalCount &&
                          _form.state == SapState.pendingReview
                      ? _uploadScan
                      : null,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.position,
    required this.displayLabel,
    this.recorded = false,
    this.signerName,
    this.onRecord,
  });

  final int slot;
  final String position;
  final String displayLabel;
  final bool recorded;
  final String? signerName;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    return BrutListRow(
      title: position,
      meta: signerName == null ? displayLabel : '$displayLabel · $signerName',
      marker: SizedBox(
        width: 26,
        child: Text('$slot', style: AppText.number.copyWith(fontSize: 18)),
      ),
      trailing: recorded
          ? const BrutBadge(label: 'Recorded', tone: BrutTone.mint)
          : onRecord == null
          ? const BrutBadge(label: 'Not yet')
          : BrutButton(
              label: 'Record',
              size: BrutSize.small,
              expand: false,
              onPressed: onRecord,
            ),
    );
  }
}

/// What SDS writes down about one signed page.
class _RecordSheet extends StatefulWidget {
  const _RecordSheet({required this.step, required this.taken});

  final SapWorkflowStep step;
  final List<SapCheckpointEvidence> taken;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  final _name = TextEditingController();
  final _reference = TextEditingController();
  final _remarks = TextEditingController();
  DateTime? _signedOn;

  @override
  void dispose() {
    _name.dispose();
    _reference.dispose();
    _remarks.dispose();
    super.dispose();
  }

  /// The rules the server applies, said here so SDS is not told four
  /// times in a row that something is wrong.
  String? get _problem {
    final name = _name.text.trim();
    final reference = _reference.text.trim();
    if (name.isEmpty) return 'Who signed it?';
    if (reference.isEmpty) {
      return 'A person reference is needed, so the same signer is not '
          'recorded twice by accident.';
    }
    if (_signedOn == null) return 'When was it signed?';
    if (_signedOn!.isAfter(DateTime.now())) {
      return 'A signature cannot be dated in the future.';
    }
    for (final e in widget.taken) {
      if (e.signerName.toLowerCase() == name.toLowerCase()) {
        return 'Slot ${widget.step.slot} needs a different person; that '
            'name is already recorded.';
      }
      if (e.signerReference.toLowerCase() == reference.toLowerCase()) {
        return 'That reference is already recorded against another slot.';
      }
    }
    return null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _signedOn ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (chosen != null) setState(() => _signedOn = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrutSectionTitle(
              'Slot ${widget.step.slot} · ${widget.step.position}',
            ),
            const SizedBox(height: 6),
            Text(
              'Recording that the paper was inspected. This does not sign '
              'anything.',
              style: AppText.caption,
            ),
            const SizedBox(height: 14),
            BrutTextField(
              controller: _name,
              label: 'Signed by',
              hint: 'Dr. Edna F. Dayao',
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            BrutTextField(
              controller: _reference,
              label: 'Person reference',
              hint: 'institution-person-004',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            BrutDateField(
              label: 'Date on the paper',
              value: _signedOn,
              hint: 'Pick the date',
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            BrutTextField(
              controller: _remarks,
              label: 'Remarks',
              hint: 'Paper inspected by SDS',
              maxLines: 2,
              onChanged: (_) => setState(() {}),
            ),
            if (problem != null) ...[
              const SizedBox(height: 14),
              BrutInlineMessage(
                tone: BrutTone.coral,
                icon: Icons.error_outline,
                text: problem,
              ),
            ],
            const SizedBox(height: 16),
            BrutButton(
              label: 'Record it',
              onPressed: problem != null
                  ? null
                  : () => Navigator.of(context).pop(
                      SapCheckpointEvidence(
                        signerName: _name.text.trim(),
                        signerReference: _reference.text.trim(),
                        // Left unset: linking an account makes the server
                        // demand the name match it exactly, and most of
                        // these signers have no account at all.
                        assignedUserId: null,
                        physicalSignatureDate: _signedOn!,
                        remarks: _remarks.text.trim().isEmpty
                            ? null
                            : _remarks.text.trim(),
                        recordedOnBehalf: true,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
