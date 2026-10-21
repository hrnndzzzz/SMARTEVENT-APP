import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/brut.dart';
import 'sap_form_fields.dart';

/// Part 6 — Evaluation.
///
/// Recorded once, after the activity, by the SDS Office. "Conducted" and
/// "canceled" both finish the administration, which is not the same as
/// the activity having happened: neither waives the closeout reports, and
/// anything counting activities has to read the outcome rather than the
/// fact that the proposal reached its final state.
class SapPart6Screen extends StatefulWidget {
  const SapPart6Screen({super.key, required this.form});

  final SapForm form;

  @override
  State<SapPart6Screen> createState() => _SapPart6ScreenState();
}

class _SapPart6ScreenState extends State<SapPart6Screen> {
  late final SapForm _form = widget.form;
  final _remarks = TextEditingController();
  SapEvaluationOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    final e = _form.proposal?.evaluation;
    if (e != null) {
      _outcome = e.outcome;
      _remarks.text = e.remarks;
    }
  }

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  bool get _recorded => _form.proposal?.evaluation != null;

  bool get _valid => _outcome != null && _remarks.text.trim().isNotEmpty;

  Future<void> _record() async {
    final ok = await _form.evaluate(
      outcome: _outcome!,
      remarks: _remarks.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_form.error ?? 'Could not record it.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _form,
      builder: (context, _) {
        return BrutScreen(
          header: BrutHeader(
            title: 'Evaluation',
            eyebrow: 'Part 6',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          footer: _recorded
              ? null
              : BrutFooter(
                  onBack: () => Navigator.of(context).maybePop(),
                  note: 'Recorded once; it cannot be changed afterwards.',
                  child: BrutButton(
                    label: 'Record evaluation',
                    busy: _form.saving,
                    busyLabel: 'Saving',
                    onPressed: _valid ? _record : null,
                  ),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SapSdsOnlyNotice(),
              const SizedBox(height: 16),

              if (_recorded)
                BrutInlineMessage(
                  tone: BrutTone.mint,
                  icon: Icons.check_circle_outline,
                  text:
                      'Recorded as '
                      '${_form.proposal!.evaluation!.outcome.label.toLowerCase()}.',
                )
              else ...[
                SapSingleChoice<SapEvaluationOutcome>(
                  label: 'Outcome',
                  options: SapEvaluationOutcome.values,
                  labelOf: (o) => o.label,
                  value: _outcome,
                  onChanged: (o) => setState(() => _outcome = o),
                ),
                const SizedBox(height: 10),
                if (_outcome == SapEvaluationOutcome.conducted)
                  const BrutInlineMessage(
                    tone: BrutTone.neutral,
                    icon: Icons.info_outline,
                    text:
                        'Recording this as conducted starts the students\' '
                        'learning-journal requirements.',
                  ),
                if (_outcome == SapEvaluationOutcome.canceled)
                  const BrutInlineMessage(
                    tone: BrutTone.neutral,
                    icon: Icons.info_outline,
                    text:
                        'A cancellation records no attendance, expenses or '
                        'journals. The closeout reports still stand.',
                  ),
              ],
              const SizedBox(height: 18),

              BrutTextField(
                controller: _remarks,
                label: 'Remarks',
                hint: 'Activity completed; reports to follow.',
                enabled: !_recorded,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        );
      },
    );
  }
}
