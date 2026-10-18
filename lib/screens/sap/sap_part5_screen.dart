import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import 'sap_form_fields.dart';

/// Part 5 — University Clearance.
///
/// Nine physical signatures, collected on paper. Nothing here signs
/// anything: SDS records that it inspected a signed page, and the
/// authoritative evidence is the scan uploaded at the end. The wording
/// throughout is deliberate about that — calling a recorded checkpoint a
/// signature would misrepresent what the system knows.
///
/// Before the first submission there are no steps at all, so the screen
/// shows the nine slots as the blank form has them.
class SapPart5Screen extends StatelessWidget {
  const SapPart5Screen({super.key, required this.form});

  final SapForm form;

  /// The nine slots in the order the paper prints them. Used for the
  /// blank view; once submitted, the server's own rows replace these and
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: form,
      builder: (context, _) {
        final submitted =
            form.state != null && form.state != SapState.draft;

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
              const SizedBox(height: 16),

              if (!submitted) ...[
                const BrutInlineMessage(
                  tone: BrutTone.sun,
                  icon: Icons.lock_clock,
                  text:
                      'The nine slots open once the proposal is submitted. '
                      'Until then this is how the printed page will look.',
                ),
                const SizedBox(height: 14),
              ],

              for (final (slot, position, label) in blankSlots) ...[
                _SlotCard(
                  slot: slot,
                  position: position,
                  displayLabel: label,
                  recorded: false,
                ),
                const SizedBox(height: 8),
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
    required this.recorded,
  });

  final int slot;
  final String position;
  final String displayLabel;
  final bool recorded;

  @override
  Widget build(BuildContext context) {
    return BrutListRow(
      title: position,
      meta: displayLabel,
      marker: SizedBox(
        width: 26,
        child: Text('$slot', style: AppText.number.copyWith(fontSize: 18)),
      ),
      trailing: BrutBadge(
        label: recorded ? 'Recorded' : 'Not yet',
        tone: recorded ? BrutTone.mint : BrutTone.neutral,
      ),
    );
  }
}
