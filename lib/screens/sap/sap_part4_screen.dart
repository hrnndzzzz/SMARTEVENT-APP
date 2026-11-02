import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import 'sap_form_fields.dart';
import 'sap_proposal_flow.dart';

/// Part 4 — SDS Office Clearance.
///
/// The SDS Office's own section: the server takes it from SDS staff alone,
/// and only while the proposal is with them. Anyone else, and the office at
/// any other time, reads what was recorded under a card that says where the
/// proposal is.
///
/// Every "not applicable" owes a reason, which the server enforces. The
/// form asks for it inline rather than letting someone discover at
/// submission that four rows need explaining.
///
/// Confirming this is also what Parts 1 to 3 clear: any later edit there
/// invalidates the clearance and SDS has to confirm again.
class SapPart4Screen extends StatefulWidget {
  const SapPart4Screen({super.key, required this.form});

  final SapForm form;

  @override
  State<SapPart4Screen> createState() => _SapPart4ScreenState();
}

class _SapPart4ScreenState extends State<SapPart4Screen> {
  late final SapForm _form = widget.form;

  late SapClearanceAnswer _consent;
  late SapClearanceAnswer _interruption;
  late SapClearanceAnswer _medical;
  late SapClearanceAnswer _compliance;

  late final _consentReason = TextEditingController();
  late final _attachments = TextEditingController();
  late final _interruptionRemarks = TextEditingController();
  late final _medicalReason = TextEditingController();
  late final _complianceReason = TextEditingController();
  late final _ratio = TextEditingController();

  @override
  void initState() {
    super.initState();
    final c = _form.clearance;
    _consent = c?.parentsConsent ?? SapClearanceAnswer.notApplicable;
    _interruption = c?.classInterruption ?? SapClearanceAnswer.none;
    _medical = c?.medicalExam ?? SapClearanceAnswer.notApplicable;
    _compliance = c?.reportOfCompliance ?? SapClearanceAnswer.notApplicable;
    _consentReason.text = c?.parentsConsentReason ?? '';
    _attachments.text = c?.attachments ?? '';
    _interruptionRemarks.text = c?.classInterruptionRemarks ?? '';
    _medicalReason.text = c?.medicalExamReason ?? '';
    _complianceReason.text = c?.reportOfComplianceReason ?? '';
    _ratio.text = c?.studentPersonnelRatio ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _consentReason,
      _attachments,
      _interruptionRemarks,
      _medicalReason,
      _complianceReason,
      _ratio,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The three rules the server applies, checked here so they can be
  /// shown next to the field rather than returned as a 422.
  String? get _problem {
    if (_consent == SapClearanceAnswer.notApplicable &&
        _consentReason.text.trim().isEmpty) {
      return 'Say why a parent\'s consent form does not apply.';
    }
    if (_medical == SapClearanceAnswer.notApplicable &&
        _medicalReason.text.trim().isEmpty) {
      return 'Say why a medical exam does not apply.';
    }
    if (_compliance == SapClearanceAnswer.notApplicable &&
        _complianceReason.text.trim().isEmpty) {
      return 'Say why a Report of Compliance does not apply.';
    }
    if (_interruption == SapClearanceAnswer.yes) {
      if (_interruptionRemarks.text.trim().isEmpty) {
        return 'Class interruption needs remarks.';
      }
      if (_form.affectedClasses.isEmpty) {
        return 'Class interruption needs the affected classes listed in '
            'Part 3.';
      }
    }
    if (_interruption == SapClearanceAnswer.none &&
        _form.affectedClasses.isNotEmpty) {
      return 'Part 3 lists affected classes, so this cannot be "none".';
    }
    if (_attachments.text.trim().isEmpty) {
      return 'Summarise the attachments, or write "none".';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _problem;
    if (problem != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    _form.setClearance(
      SapClearance(
        parentsConsent: _consent,
        parentsConsentReason: _consent == SapClearanceAnswer.notApplicable
            ? _consentReason.text.trim()
            : null,
        attachments: _attachments.text.trim(),
        classInterruption: _interruption,
        classInterruptionRemarks: _interruption == SapClearanceAnswer.yes
            ? _interruptionRemarks.text.trim()
            : null,
        medicalExam: _medical,
        medicalExamReason: _medical == SapClearanceAnswer.notApplicable
            ? _medicalReason.text.trim()
            : null,
        reportOfCompliance: _compliance,
        reportOfComplianceReason:
            _compliance == SapClearanceAnswer.notApplicable
            ? _complianceReason.text.trim()
            : null,
        studentPersonnelRatio: _ratio.text.trim(),
      ),
    );

    final ok = await _form.saveClearance();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_form.error ?? 'Could not save.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _form,
      builder: (context, _) {
        // `isReadOnly` is the session being offline or signed out, which
        // says nothing about whose account this is.
        final editable =
            SapProposalFlow.isSdsStaff(context) &&
            _form.state == SapState.pendingReview &&
            !_form.isReadOnly;
        // Nothing to put right for someone who cannot change it.
        final problem = editable ? _problem : null;
        // With nothing recorded the answers are only what initState seeds, a
        // starting point for the office to fill in. To anyone else they would
        // read as the office saying "Not applicable" with no reason.
        final showAnswers = editable || _form.clearance != null;

        return BrutScreen(
          header: BrutHeader(
            title: 'SDS Office Clearance',
            eyebrow: 'Part 4',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          // One back button, in the header, as Parts 1 to 3 and 5 all
          // have. Two doing the same thing is what the review called out.
          footer: BrutFooter(
            child: BrutButton(
              label: 'Confirm clearance',
              busy: _form.saving,
              busyLabel: 'Saving',
              onPressed: editable ? _save : null,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SapSdsOnlyNotice(),
              const SizedBox(height: 16),
              if (!editable) ...[
                _Outcome(form: _form),
                const SizedBox(height: 20),
              ],
              if (showAnswers) ...[
                SapSingleChoice<SapClearanceAnswer>(
                  enabled: editable,
                  label: 'Parent\'s consent form',
                  options: const [
                    SapClearanceAnswer.yes,
                    SapClearanceAnswer.notApplicable,
                  ],
                  labelOf: (a) => a.label,
                  value: _consent,
                  onChanged: (a) => setState(
                    () => _consent = a ?? SapClearanceAnswer.notApplicable,
                  ),
                ),
                if (_consent == SapClearanceAnswer.notApplicable) ...[
                  const SizedBox(height: 10),
                  BrutTextField(
                    enabled: editable,
                    controller: _consentReason,
                    label: 'Why not',
                    maxLength: 5000,
                    hint: 'Online activity',
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 20),

                BrutTextField(
                  enabled: editable,
                  controller: _attachments,
                  label: 'Attachments',
                  maxLength: 5000,
                  hint: 'Program flow and budget',
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),

                SapSingleChoice<SapClearanceAnswer>(
                  enabled: editable,
                  label: 'Academic class interruption',
                  options: const [
                    SapClearanceAnswer.yes,
                    SapClearanceAnswer.none,
                  ],
                  labelOf: (a) => a.label,
                  value: _interruption,
                  onChanged: (a) => setState(
                    () => _interruption = a ?? SapClearanceAnswer.none,
                  ),
                ),
                if (_interruption == SapClearanceAnswer.yes) ...[
                  const SizedBox(height: 10),
                  BrutTextField(
                    enabled: editable,
                    controller: _interruptionRemarks,
                    label: 'Remarks',
                    maxLength: 5000,
                    hint: 'Excuse letters required',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  BrutInlineMessage(
                    tone: _form.affectedClasses.isEmpty
                        ? BrutTone.coral
                        : BrutTone.neutral,
                    icon: Icons.school_outlined,
                    text: _form.affectedClasses.isEmpty
                        ? 'Part 3 lists no affected classes. It has to list at '
                              'least one for this answer.'
                        : '${_form.affectedClasses.length} class(es) listed in '
                              'Part 3.',
                  ),
                ],
                const SizedBox(height: 20),

                SapSingleChoice<SapClearanceAnswer>(
                  enabled: editable,
                  label: 'Medical exam request',
                  options: const [
                    SapClearanceAnswer.yes,
                    SapClearanceAnswer.notApplicable,
                  ],
                  labelOf: (a) => a.label,
                  value: _medical,
                  onChanged: (a) => setState(
                    () => _medical = a ?? SapClearanceAnswer.notApplicable,
                  ),
                ),
                if (_medical == SapClearanceAnswer.notApplicable) ...[
                  const SizedBox(height: 10),
                  BrutTextField(
                    enabled: editable,
                    controller: _medicalReason,
                    label: 'Why not',
                    maxLength: 5000,
                    hint: 'Online activity',
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 20),

                SapSingleChoice<SapClearanceAnswer>(
                  enabled: editable,
                  label: 'Report of Compliance (CMO 63 s.2017)',
                  options: const [
                    SapClearanceAnswer.yes,
                    SapClearanceAnswer.notApplicable,
                  ],
                  labelOf: (a) => a.label,
                  value: _compliance,
                  onChanged: (a) => setState(
                    () => _compliance = a ?? SapClearanceAnswer.notApplicable,
                  ),
                ),
                if (_compliance == SapClearanceAnswer.notApplicable) ...[
                  const SizedBox(height: 10),
                  BrutTextField(
                    enabled: editable,
                    controller: _complianceReason,
                    label: 'Why not',
                    maxLength: 5000,
                    hint: 'No off-campus travel',
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 20),

                BrutTextField(
                  enabled: editable,
                  controller: _ratio,
                  label: 'Student-personnel ratio',
                  maxLength: 5000,
                  hint: '145:3',
                  onChanged: (_) => setState(() {}),
                ),
                if (problem case final message?) ...[
                  const SizedBox(height: 16),
                  BrutInlineMessage(
                    tone: BrutTone.coral,
                    icon: Icons.error_outline,
                    text: message,
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Where Part 4 stands, for anyone who cannot change it: who has the
/// proposal, or what the SDS Office decided, and what it said.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.form});

  final SapForm form;

  /// Only a return by the office is its outcome: the Moderator or Dean
  /// sending it back says nothing about this part. An older server does not
  /// say who, and then it was always the office. Read only for a returned
  /// proposal, the only time [SapForm.returnedBy] means anything.
  bool get _returnedByOffice =>
      form.returnedBy == null || form.returnedBy == SapReturnedBy.sds;

  @override
  Widget build(BuildContext context) {
    final (line, detail, tone) = switch (form.state) {
      SapState.pendingDepartmentReview => (
        'With the Moderator and Dean',
        'The SDS Office checks this part after both have approved the '
            'proposal.',
        BrutTone.sun,
      ),
      SapState.pendingReview => (
        'With the SDS Office',
        'The SDS Office is checking this part. Its answers are recorded '
            'here once it confirms them.',
        BrutTone.sun,
      ),
      SapState.revisionRequested when _returnedByOffice => (
        'Needs revision',
        'The SDS Office sent the proposal back. It checks this part again '
            'when the proposal is sent again.',
        BrutTone.coral,
      ),
      SapState.sdsSigned || SapState.approved || SapState.completed => (
        'Approved',
        'The SDS Office has confirmed this part.',
        BrutTone.mint,
      ),
      SapState.rejected => (
        'Rejected',
        'The SDS Office rejected this proposal. It is final.',
        BrutTone.coral,
      ),
      // A draft, or one the Moderator or Dean returned: the office has not
      // had this round of it.
      _ => (
        'Not with the SDS Office yet',
        'It goes to the Moderator and Dean first, then the SDS Office.',
        BrutTone.neutral,
      ),
    };
    final remarks = form.sdsRemarkLines(overall: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const SizedBox(height: 16),
        const BrutSectionTitle('SDS Office remarks'),
        const SizedBox(height: 8),
        BrutInlineMessage(
          tone: BrutTone.neutral,
          icon: Icons.chat_bubble_outline,
          text: remarks.isEmpty
              ? 'No remarks from the SDS Office yet.'
              : remarks.join('\n'),
        ),
      ],
    );
  }
}
