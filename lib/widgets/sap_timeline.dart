import 'package:flutter/material.dart';

import '../api/models/sap_proposal.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// Where a proposal has got to, as the whole journey rather than one word.
///
/// A proposal passes through six hands and the form only ever said which
/// one held it right now — "With the department" tells a proposer nothing
/// about what is behind them or what is still to come. This draws every
/// stop, marks the ones that are done, and names who has it.
///
/// ## The two ways off the path
///
/// A return and a rejection are not stops, they are interruptions, and
/// they are drawn differently. A **return** sends the proposal back to
/// the proposer, so the marker sits on the stop it came back to and the
/// stops beyond it go pale again — the work ahead is real work, not
/// history. A **rejection** is final: it stops at the SDS Office and
/// nothing after it will happen, so the remaining stops are struck
/// through rather than merely waiting.
class SapTimeline extends StatelessWidget {
  const SapTimeline({super.key, required this.state});

  final SapState state;

  /// The stops, in the order the paper moves through them.
  static const _stops = <({String name, String who})>[
    (name: 'Draft', who: 'Yours to fill in'),
    (name: 'The department', who: 'The Moderator, then the Dean'),
    (name: 'The SDS Office', who: 'Checked against the paper form'),
    (name: 'Signed', who: 'Printed for the physical signatures'),
    (name: 'Approved', who: 'Cleared to run'),
    (name: 'Completed', who: 'Evaluated and closed'),
  ];

  /// Which stop the proposal is standing at.
  ///
  /// A return puts it back at the stop it came from — the department or
  /// the office returned it *to the proposer*, so that is where it is.
  static int indexFor(SapState state) => switch (state) {
    SapState.draft => 0,
    SapState.revisionRequested => 0,
    SapState.pendingDepartmentReview => 1,
    SapState.pendingReview => 2,
    SapState.rejected => 2,
    SapState.sdsSigned => 3,
    SapState.approved => 4,
    SapState.completed => 5,
  };

  bool get _returned => state == SapState.revisionRequested;
  bool get _rejected => state == SapState.rejected;

  /// What the marker says at the current stop, when it is not simply
  /// "here".
  String? get _interruption {
    if (_rejected) return 'Rejected — final';
    // Who returned it and why is in the banner directly below, with
    // the remarks attached. Saying it here too put the same sentence
    // on the screen twice.
    if (_returned) return 'Returned to you';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final here = indexFor(state);
    final trouble = _returned || _rejected;
    final mark = trouble ? BrutTone.coral : BrutTone.brand;

    return Semantics(
      container: true,
      label:
          'Progress: ${_stops[here].name}, step ${here + 1} of '
          '${_stops.length}${_interruption == null ? '' : '. ${_interruption!}'}',
      child: BrutCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: MonoLabel('Where it has got to')),
                MonoLabel(
                  'STEP ${here + 1} / ${_stops.length}',
                  color: p.muted,
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _stops.length; i++)
              _Stop(
                stop: _stops[i],
                // Everything before the current stop has happened,
                // whichever way the proposal is going.
                done: i < here,
                current: i == here,
                // After a rejection nothing more will happen; after a
                // return the rest is still ahead.
                dead: _rejected && i > here,
                last: i == _stops.length - 1,
                tone: i == here ? mark : BrutTone.mint,
                note: i == here ? _interruption : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({
    required this.stop,
    required this.done,
    required this.current,
    required this.dead,
    required this.last,
    required this.tone,
    required this.note,
  });

  final ({String name, String who}) stop;
  final bool done;
  final bool current;
  final bool dead;
  final bool last;
  final BrutTone tone;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fill = done || current ? tone.fill(context) : p.canvas;
    final ink = dead ? p.subtle : p.ink;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The rail: a dot, and the line down to the next one. Drawn
          // here rather than behind the row so it cannot drift out of
          // step with the text beside it at a larger font size.
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: dead ? p.subtle : p.ink,
                      width: AppBorders.width,
                    ),
                  ),
                  child: done ? Icon(Icons.check, size: 9, color: p.ink) : null,
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: dead ? p.subtle : p.ink,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 8 : 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name,
                    style: AppText.body.copyWith(
                      fontSize: 14,
                      height: 1.1,
                      color: ink,
                      fontWeight: current ? FontWeight.w500 : FontWeight.w400,
                      decoration: dead ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note ?? stop.who,
                    style: AppText.caption.copyWith(
                      color: note == null ? p.muted : tone.fill(context),
                      fontWeight: note == null
                          ? FontWeight.w400
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
