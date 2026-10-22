import 'package:flutter/material.dart';

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
  static const List<String> labels = ['Activity', 'Support', 'Breakdown'];

  static const int activity = 0;
  static const int support = 1;
  static const int breakdown = 2;

  static int get count => labels.length;
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
  static Future<bool> confirm(
    BuildContext context, {
    required Future<bool> Function() save,
  }) async {
    final choice = await showDialog<_Leaving>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this proposal?'),
        content: const Text(
          'Nothing has been sent to the SDS Office yet. You can keep what '
          'you have written as a draft and come back to it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_Leaving.stay),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_Leaving.discard),
            child: const Text('Go back'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_Leaving.save),
            child: const Text('Save as draft'),
          ),
        ],
      ),
    );

    switch (choice) {
      case null:
      case _Leaving.stay:
        return false;
      case _Leaving.discard:
        return true;
      case _Leaving.save:
        return save();
    }
  }

}

enum _Leaving { stay, discard, save }
