import 'package:flutter/material.dart';

import '../../state/sap_form.dart';
import '../../theme/brut.dart';
import 'sap_proposal_flow.dart';

/// Filling in the proposal, as its three parts.
///
/// They are the form's own parts and nothing else. An earlier version
/// put the create-event screen's two steps in front of these, which
/// made the bar describe the app's plumbing rather than the paper the
/// person is filling in.
///
/// Parts 4 to 6 are the SDS Office's and are not steps here: a bar a
/// proposer cannot finish is worse than no bar.
abstract final class ProposalSteps {
  /// Part 1 is three steps rather than one.
  ///
  /// It carried about twenty-five fields and two collections on a
  /// single scroll, and the people who tried it said there was too much
  /// happening. The groups it was already drawn in — the activity, when
  /// and where, then everything describing it — are now a step each, so
  /// the bar counts five rather than three.
  ///
  /// Parts 4 to 6 are the SDS Office's and are still not steps here: a
  /// bar a proposer cannot finish is worse than no bar.
  static const List<String> labels = [
    'Activity',
    'Schedule',
    'Details',
    'Support',
    'Breakdown',
  ];

  static const int activity = 0;
  static const int schedule = 1;
  static const int details = 2;
  static const int support = 3;
  static const int breakdown = 4;

  /// The three that make up Part 1, in order.
  static const List<int> partOne = [activity, schedule, details];

  /// The last of Part 1 — where the event record is created, because
  /// only by here are the title and the date both in hand.
  static const int partOneEnd = details;

  static int get count => labels.length;

  /// Which step the field called [label] is on.
  ///
  /// The labels are `SapForm.missingForSubmit`'s, so that "Send for
  /// review" can say not only what is missing but where it is. Before
  /// this the button simply went dead: everything required lives on
  /// steps the proposer has already left, the list of what was missing
  /// was drawn at the top of the last step, and the button is at the
  /// bottom — so by the time you pressed it, the explanation was a
  /// screen and a half above your thumb.
  ///
  /// Nearly everything is on Part 1, which is why [details] is the
  /// fallback rather than a thrown error: it carries thirteen of the
  /// twenty-eight, and a label this list has not heard of is far better
  /// sent to the longest step than to none.
  static int stepForMissing(String label) => switch (label) {
    'Activity title' ||
    'Organization' ||
    'Department type' ||
    'Department' ||
    'School year' ||
    'Date of proposal' => activity,
    'Activity date' ||
    'Start time' ||
    'End time' ||
    'Modality' ||
    'Setting' ||
    'Off-campus agreement' ||
    'ROC / COC attachment' ||
    'Venue' => schedule,
    'Budget breakdown that adds up to the budget' => breakdown,
    // Blocks sending, not the step: the draft can still be saved and
    // the budget changed later, as the available balance moves.
    final over when over.startsWith('Budget within the available') =>
      breakdown,
    _ => details,
  };

  /// What [form] is still missing *on this step alone*.
  ///
  /// The same labels [stepForMissing] routes, filtered to one step, so
  /// Next can refuse a page for its own gaps without naming fields the
  /// proposer has not reached yet. Asking for all twenty-eight on step
  /// one would refuse a page that had been filled in correctly.
  static List<String> missingOn(SapForm form, int step) => [
    for (final label in form.missingForSubmit)
      if (stepForMissing(label) == step) label,
  ];
}

/// Leaving a part-filled proposal.
///
/// The three steps each carried two back buttons — one in the header and
/// one in the footer — which did the same thing and left it unclear
/// whether anything had been kept. There is one now, in the header, and
/// it asks.
abstract final class LeaveProposal {
  /// Returns true when the caller should leave, having saved if asked.
  ///
  /// [save] is awaited before leaving, so a draft that fails to save
  /// keeps the person on the screen with their work rather than
  /// dropping them out of it.
  ///
  /// "Go back" promises nothing is kept, so a draft event [form] made on
  /// the way out of Part 1 is deleted with it. Left on the server, it was
  /// the first of two events with the same title once the proposer started
  /// again. "Save as draft" keeps it for good.
  static Future<bool> confirm(
    BuildContext context, {
    required Future<bool> Function() save,
    SapForm? form,
  }) async {
    final choice = await showDialog<_Leaving>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this proposal?'),
        // Stacked, full width, one line each.
        //
        // They were three boxes across a dialog, so each got a third of
        // it: "Cancel" and "Go back" fitted, "Save as draft" wrapped to
        // two lines, and an IntrinsicHeight then made all three as tall
        // as the tallest. Three different shapes for three choices of
        // equal weight.
        //
        // Ordered by what they do, not by habit: keeping the work
        // first, losing it last, and the one that loses it says so.
        // "Go back" read as returning to the form, which is the
        // opposite of what it does.
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nothing has been sent yet. You can keep what you have '
              'written as a draft and come back to it.',
            ),
            const SizedBox(height: 18),
            BrutButton(
              label: 'Save as draft',
              icon: Icons.bookmark_outline,
              onPressed: () => Navigator.of(dialogContext).pop(_Leaving.save),
            ),
            const SizedBox(height: 8),
            BrutButton(
              label: 'Leave without saving',
              icon: Icons.delete_outline,
              // The one choice here that loses work, and the only one
              // that needs to look like it.
              tone: BrutTone.coral,
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_Leaving.discard),
            ),
            const SizedBox(height: 8),
            BrutButton(
              label: 'Stay here',
              icon: Icons.close,
              tone: BrutTone.neutral,
              onPressed: () => Navigator.of(dialogContext).pop(_Leaving.stay),
            ),
          ],
        ),
      ),
    );

    switch (choice) {
      case null:
      case _Leaving.stay:
        return false;
      case _Leaving.discard:
        if (form != null && context.mounted) {
          await SapProposalFlow.discardMadeEvent(context, form);
        }
        return true;
      case _Leaving.save:
        final saved = await save();
        if (saved) form?.keepEvent();
        return saved;
    }
  }
}

enum _Leaving { stay, discard, save }
