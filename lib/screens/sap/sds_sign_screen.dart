import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import 'sap_form_fields.dart';
import 'signature_pad.dart';

/// The SDS Office's review of a pending revision: remarks, then either
/// send it back or sign it.
///
/// Remarks can be saved as often as the office likes. Signing cannot be
/// undone — it locks the revision and stores the signed PDF — so it
/// confirms first, and says plainly what it is about to do.
class SdsSignScreen extends StatefulWidget {
  const SdsSignScreen({super.key, required this.form});

  final SapForm form;

  @override
  State<SdsSignScreen> createState() => _SdsSignScreenState();
}

class _SdsSignScreenState extends State<SdsSignScreen> {
  SapForm get _form => widget.form;

  late final _overall = TextEditingController(text: _form.overallRemarks);
  final Map<SapRemarkSection, TextEditingController> _sections = {
    for (final s in SapRemarkSection.values) s: TextEditingController(),
  };

  SapSignature _signature = const SapSignature([]);

  @override
  void initState() {
    super.initState();
    for (final entry in _form.sectionRemarks.entries) {
      _sections[entry.key]?.text = entry.value;
    }
  }

  @override
  void dispose() {
    _overall.dispose();
    for (final c in _sections.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Only a revision that is waiting can be reviewed. A signed one is
  /// locked, and a draft has not been sent yet.
  bool get _open => _form.state == SapState.pendingReview;

  void _collect() {
    _form.overallRemarks = _overall.text.trim();
    _form.sectionRemarks = {
      for (final entry in _sections.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
    };
  }

  Future<void> _saveNotes() async {
    _collect();
    final problem = await _form.saveReviewNotes();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(problem ?? 'Remarks saved.')),
    );
  }

  Future<void> _sign() async {
    final problem = _signature.problem;
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(problem)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign this proposal?'),
        content: const Text(
          'This locks the revision and stores the signed form. It cannot '
          'be undone: a proposal that needs changing afterwards has to be '
          'returned and signed again as a new revision.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _collect();
    final failure = await _form.sdsSign(_signature);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failure ?? 'Signed. The form is locked.')),
    );
    if (failure == null) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _form,
      builder: (context, _) {
        return BrutScreen(
          header: BrutHeader(
            title: 'Review and sign',
            eyebrow: 'SDS Office',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          // One back button, in the header, as on the three steps.
          footer: BrutFooter(
            child: BrutButton(
              label: 'Sign the proposal',
              icon: Icons.draw_outlined,
              busy: _form.saving,
              busyLabel: 'Signing',
              onPressed: _open && _signature.isSendable ? _sign : null,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SapSdsOnlyNotice(),
              const SizedBox(height: 16),

              if (!_open)
                BrutInlineMessage(
                  tone: BrutTone.neutral,
                  icon: Icons.lock_outline,
                  text: _form.state == SapState.sdsSigned
                      ? 'This revision is signed. Return it to make changes.'
                      : 'Only a proposal waiting on the SDS Office can be '
                            'reviewed here.',
                ),
              if (!_open) const SizedBox(height: 16),

              const BrutSectionTitle('Remarks'),
              const SizedBox(height: 10),
              BrutTextField(
                controller: _overall,
                label: 'Overall',
                hint: 'What the proposer should know',
                enabled: _open,
                maxLines: 4,
              ),
              const SizedBox(height: 16),

              Text(
                'Against a section, if it belongs to one:',
                style: AppText.caption,
              ),
              const SizedBox(height: 10),
              for (final section in SapRemarkSection.values) ...[
                BrutTextField(
                  controller: _sections[section]!,
                  label: section.label,
                  enabled: _open,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
              ],

              const SizedBox(height: 6),
              BrutButton(
                label: 'Save remarks',
                tone: BrutTone.neutral,
                busy: _form.saving,
                busyLabel: 'Saving',
                onPressed: _open ? _saveNotes : null,
              ),

              const SizedBox(height: 24),
              const BrutSectionTitle('Signature'),
              const SizedBox(height: 10),
              SapSignaturePad(
                enabled: _open,
                onChanged: (s) => setState(() => _signature = s),
              ),
              const SizedBox(height: 10),
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.info_outline,
                text:
                    'This is the one electronic signature on the form. The '
                    'nine on paper stay paper.',
              ),
            ],
          ),
        );
      },
    );
  }
}
