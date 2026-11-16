import 'package:flutter/material.dart';

import '../../state/sap_form.dart';
import '../../theme/brut.dart';
import '../../widgets/report_tiles.dart';
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
    _ => details,
  };
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
        // The three choices are squared boxes, the same shape the
        // reports screen uses for a set of actions, rather than the
        // stacked text links an AlertDialog gives by default — which
        // looked nothing like the rest of the app and read as a list
        // of links rather than a choice between three things.
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nothing has been sent yet. You can keep what you have '
              'written as a draft and come back to it.',
            ),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ReportActionTile(
                      label: 'Cancel',
                      icon: Icons.close,
                      dense: true,
                      onTap: () =>
                          Navigator.of(dialogContext).pop(_Leaving.stay),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ReportActionTile(
                      label: 'Go back',
                      icon: Icons.arrow_back,
                      dense: true,
                      // It leaves without keeping anything, which is the
                      // one choice here that loses work.
                      tone: BrutTone.coral,
                      onTap: () =>
                          Navigator.of(dialogContext).pop(_Leaving.discard),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ReportActionTile(
                      label: 'Save as draft',
                      icon: Icons.bookmark_outline,
                      dense: true,
                      tone: BrutTone.brand,
                      onTap: () =>
                          Navigator.of(dialogContext).pop(_Leaving.save),
                    ),
                  ),
                ],
              ),
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
