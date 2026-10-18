import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import 'sap_part1_screen.dart';
import 'sap_part2_screen.dart';
import 'sap_part3_screen.dart';
import 'sap_part4_screen.dart';
import 'sap_part5_screen.dart';
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
  @override
  void initState() {
    super.initState();
    widget.form.load();
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
                    const BrutInlineMessage(
                      tone: BrutTone.sun,
                      icon: Icons.cloud_off,
                      text:
                          'This backend has no proposal-form routes yet, so '
                          'everything here stays on this phone until it does.',
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
                  for (final part in SapPart.values) ...[
                    _PartRow(
                      part: part,
                      status: form.statusOf(part),
                      onTap: () => _open(part),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 10),
                  const BrutInlineMessage(
                    tone: BrutTone.neutral,
                    icon: Icons.print_outlined,
                    text:
                        'Printing uses the university\'s own six-page layout, '
                        'produced by the server so the paper always matches '
                        'the record. Nine signature slots print empty, to be '
                        'signed by hand.',
                  ),
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
      meta: part.isSdsOnly ? 'Part ${part.number} · SDS Office' : 'Part ${part.number}',
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
