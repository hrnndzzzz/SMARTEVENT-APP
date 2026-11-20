import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// How a piece of work ended.
enum OutcomeKind {
  /// Still running. Nothing has happened yet and nothing can be
  /// dismissed.
  working,

  /// It went through.
  done,

  /// It did not, and the person can try again.
  problem,
}

/// A modal that says what just happened and stays until it is dismissed.
///
/// ## Why not a snackbar
///
/// The app reports most things in a snackbar, which is right for a small
/// acknowledgement: it is cheap, it does not interrupt, and it goes away
/// on its own. It is wrong for the end of the thing somebody came to do.
/// Submitting a six-part proposal and getting a strip at the bottom of
/// the screen for four seconds, which may well be missed, leaves the
/// proposer unsure whether it went. So this is deliberately not applied
/// everywhere — only where the work was substantial enough that a person
/// would otherwise go and check.
///
/// ## Why it owns the waiting too
///
/// The three states are one modal rather than three, because they are
/// one moment: the work starts, it ends, and the person watches. Showing
/// a spinner somewhere and a dialog somewhere else makes the ending look
/// unrelated to the beginning. [runWithOutcome] drives the whole
/// sequence from a Future.
class OutcomeSheet extends StatelessWidget {
  const OutcomeSheet({
    super.key,
    required this.kind,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final OutcomeKind kind;
  final String title;
  final String? body;

  /// A second button beside Close, for the one thing worth doing next —
  /// trying again, or going to look at what was made.
  final String? actionLabel;
  final VoidCallback? onAction;

  BrutTone get _tone => switch (kind) {
    OutcomeKind.working => BrutTone.neutral,
    OutcomeKind.done => BrutTone.mint,
    OutcomeKind.problem => BrutTone.coral,
  };

  IconData get _icon => switch (kind) {
    // Never drawn: the working state shows a spinner instead.
    OutcomeKind.working => Icons.more_horiz,
    OutcomeKind.done => Icons.check,
    OutcomeKind.problem => Icons.priority_high,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final working = kind == OutcomeKind.working;

    return PopScope(
      // While the work is running there is nothing to go back to and
      // nothing to cancel, so back does not close it. Dismissing a
      // dialog does not stop a request that is already in flight, and a
      // closed dialog would leave the person believing it did.
      canPop: !working,
      child: BrutSheet(
        title: title,
        subtitle: body,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Center(
              child: Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: _tone.fill(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: p.ink, width: AppBorders.width),
                ),
                child: working
                    ? const Center(child: BrutSpinner(size: 30))
                    : Icon(
                        _icon,
                        size: 40,
                        color: context.foregroundOn(_tone.fill(context)),
                      ),
              ),
            ),
            const SizedBox(height: 22),
            if (!working) ...[
              if (actionLabel != null) ...[
                BrutButton(
                  label: actionLabel!,
                  tone: kind == OutcomeKind.problem
                      ? BrutTone.coral
                      : BrutTone.brand,
                  onPressed: () {
                    Navigator.of(context).pop();
                    onAction?.call();
                  },
                ),
                const SizedBox(height: 10),
              ],
              BrutButton(
                label: 'Close',
                tone: actionLabel == null ? BrutTone.dark : BrutTone.neutral,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// Runs [work] behind a modal that waits, then says how it went.
///
/// Returns what [work] returned, or null when it threw — the caller
/// still decides what to do next, this only reports.
///
/// The modal is replaced rather than stacked: the waiting sheet is
/// closed and the result opened in its place, so there is never a
/// finished sheet with a spinner behind it.
Future<T?> runWithOutcome<T>(
  BuildContext context, {
  required Future<T> Function() work,
  required String working,
  required String done,
  String? doneBody,
  String? problem,
  String? actionLabel,
  VoidCallback? onAction,
}) async {
  final navigator = Navigator.of(context);

  BrutSheet.show<void>(
    context,
    builder: (_) => OutcomeSheet(kind: OutcomeKind.working, title: working),
  );

  T? result;
  Object? failure;
  try {
    result = await work();
  } catch (error) {
    failure = error;
  }

  // The waiting sheet is still up unless the whole screen went away
  // underneath it, which happens if the work navigated.
  if (!navigator.mounted) return result;
  navigator.pop();

  if (!context.mounted) return result;
  await BrutSheet.show<void>(
    context,
    builder: (_) => failure == null
        ? OutcomeSheet(
            kind: OutcomeKind.done,
            title: done,
            body: doneBody,
            actionLabel: actionLabel,
            onAction: onAction,
          )
        : OutcomeSheet(
            kind: OutcomeKind.problem,
            title: problem ?? 'That did not go through',
            // The thrown message, which the API layer writes for
            // people rather than for logs.
            body: '$failure',
            actionLabel: 'Try again',
            onAction: onAction,
          ),
  );
  return result;
}
