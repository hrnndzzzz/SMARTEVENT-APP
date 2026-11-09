import 'package:flutter/material.dart';

import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import 'proposal_steps.dart';
import 'sap_part1_screen.dart';
import 'sap_part2_screen.dart';
import 'sap_part3_screen.dart';

/// The three steps, side by side.
///
/// They used to be three pushed routes, so the only way between them was
/// the button at the bottom and the back arrow at the top: going from
/// the breakdown to check something on the activity meant backing out of
/// two screens and finding your way in again.
///
/// One screen holding three pages now. The buttons still move you on,
/// and so does a swipe.
class SapStepsScreen extends StatefulWidget {
  const SapStepsScreen({
    super.key,
    required this.form,
    required this.onCreateEvent,
    required this.onSubmit,
  });

  final SapForm form;

  /// Run on the way out of Part 1, which is where the event record is
  /// made from what Part 1 says. False when it was not made; Part 1 is
  /// not left then, because nothing after it could be sent.
  final Future<bool> Function(BuildContext context) onCreateEvent;

  /// Run at the end of Part 3.
  final Future<void> Function(BuildContext context) onSubmit;

  @override
  State<SapStepsScreen> createState() => _SapStepsScreenState();
}

class _SapStepsScreenState extends State<SapStepsScreen> {
  final _pages = PageController();

  /// An event record is being asked for right now. A failed attempt
  /// clears this, so the next Next or swipe tries again.
  bool _creating = false;

  /// Makes sure the event exists before anything past Part 1.
  Future<bool> _ensureEvent(BuildContext context) async {
    if (widget.form.hasEvent) return true;
    // The first attempt is still out; it moves back to Part 1 itself if
    // it fails, so a second one here would only race it.
    if (_creating) return true;
    _creating = true;
    try {
      return await widget.onCreateEvent(context);
    } finally {
      _creating = false;
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _goTo(int step) async {
    if (!_pages.hasClients) return;
    await _pages.animateToPage(
      step,
      duration: AppMotion.sheet,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pages,
      // Swiping is off. The event record is made on the way out of Part
      // 1, and a swipe past it skipped that — the submission at the end
      // then had nothing to attach itself to. Moving happens through
      // Next, or through the step bar, both of which go through here.
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final section in ProposalSteps.partOne)
          SapPart1Screen(
            form: widget.form,
            step: section,
            onCreateEvent: _ensureEvent,
            onJumpTo: _goTo,
            onContinue: (partContext) async {
              // Only the last of the three makes the event: the title
              // is on the first step and the date on the second, and
              // the record needs both.
              if (section == ProposalSteps.partOneEnd) {
                if (!await _ensureEvent(partContext)) return;
                if (!partContext.mounted) return;
                await _goTo(ProposalSteps.support);
                return;
              }
              await _goTo(section + 1);
            },
          ),
        SapPart2Screen(
          form: widget.form,
          step: ProposalSteps.support,
          onJumpTo: _goTo,
          onContinue: (_) => _goTo(ProposalSteps.breakdown),
        ),
        SapPart3Screen(
          form: widget.form,
          step: ProposalSteps.breakdown,
          onJumpTo: _goTo,
          onContinue: widget.onSubmit,
        ),
      ],
    );
  }
}
