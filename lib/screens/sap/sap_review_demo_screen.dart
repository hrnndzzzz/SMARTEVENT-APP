import 'package:flutter/material.dart';

import '../../state/sap_notes.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import '../../widgets/sap_note_mark.dart';

/// Reviewing a proposal the way the paper is reviewed.
///
/// The approved copy of Hack the Future comes back covered in marks:
/// ticks beside the budget lines, "Noted" in the diverse-needs box, and
/// a note under the affected classes asking whether the activity could
/// move to the afternoon. None of that is a decision on the proposal as
/// a whole — it is attached to one part of the form at a time, and that
/// is what makes it useful.
///
/// Runs entirely on the device. Nothing here needs a backend, so it can
/// be shown on a phone with no network at all.
class SapReviewDemoScreen extends StatefulWidget {
  const SapReviewDemoScreen({
    super.key,
    this.reviewer = 'Engr. Aileen M. Habaradas',
    this.reviewerRole = 'Moderator',
  });

  final String reviewer;
  final String reviewerRole;

  @override
  State<SapReviewDemoScreen> createState() => _SapReviewDemoScreenState();
}

class _SapReviewDemoScreenState extends State<SapReviewDemoScreen> {
  final SapNotes _notes = SapNotes(eventId: 'demo-hack-the-future');

  @override
  void initState() {
    super.initState();
    _notes.load().then((_) {
      if (_notes.total == 0) _notes.seedFromPaper();
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  SapNoteMark _mark(String anchor, String title) => SapNoteMark(
    notes: _notes,
    anchor: anchor,
    title: title,
    author: widget.reviewer,
    authorRole: widget.reviewerRole,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _notes,
      builder: (context, _) {
        final open = _notes.openChangeCount;

        return BrutScreen(
          header: BrutHeader(
            title: 'Review',
            eyebrow: 'SAS-SDS-FO-020 · Hack the Future',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          footer: BrutFooter(
            note: open == 0
                ? '${_notes.total} mark(s), nothing outstanding'
                : '$open change(s) still to make',
            child: BrutButton(
              label: open == 0 ? 'Send it on' : 'Return for revision',
              tone: open == 0 ? BrutTone.brand : BrutTone.coral,
              icon: open == 0 ? Icons.outbox : Icons.undo,
              onPressed: () => _finish(open),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrutInlineMessage(
                tone: open == 0 ? BrutTone.neutral : BrutTone.coral,
                icon: Icons.edit_note,
                text: open == 0
                    ? 'Tap the mark beside any part to read what was '
                          'written there, or to add your own.'
                    : 'One or more parts need a change before this can go '
                          'further. Tap the red marks to read them.',
              ),
              const SizedBox(height: 18),

              _Section(
                title: 'Activity details',
                eyebrow: 'Part 1',
                mark: _mark('part1.activity', 'Activity details'),
                rows: const [
                  (
                    'Title',
                    'HACK THE FUTURE: Cybersecurity, Ethical '
                        'Hacking, and the Battle for the Digital World',
                  ),
                  (
                    'Organization',
                    'Association of Computer Engineering '
                        'Students',
                  ),
                  ('Date', '28 October 2026 · 8:00 AM – 11:00 AM'),
                  ('Modality', 'Online · Zoom Platform'),
                  ('Students', '145'),
                ],
              ),
              const SizedBox(height: 10),
              _Section(
                title: 'Augustinian core values',
                eyebrow: 'Part 1',
                mark: _mark('part1.core_values', 'Augustinian core values'),
                rows: const [('Ticked', 'All six')],
              ),
              const SizedBox(height: 10),
              _Section(
                title: 'Expected graduate attributes',
                eyebrow: 'Part 1',
                mark: _mark('part1.egas', 'Expected graduate attributes'),
                rows: const [('Ticked', 'EGA 1 to 4')],
              ),
              const SizedBox(height: 10),
              _Section(
                title: 'Provision for diverse needs',
                eyebrow: 'Part 2',
                mark: _mark('part2.diverse_needs', 'Diverse needs'),
                rows: const [
                  (
                    'Declared',
                    'None of the participating students require specific '
                        'accommodations.',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Section(
                title: 'Budget breakdown',
                eyebrow: 'Part 3',
                mark: _mark('part3.budget', 'Budget breakdown'),
                rows: const [
                  ('Guest speaker', '₱2,000.00'),
                  ('Certificate and token', '₱300.00'),
                  ('Seminar materials', '₱200.00'),
                  ('Total', '₱2,500.00'),
                ],
              ),
              const SizedBox(height: 10),
              _Section(
                title: 'Affected classes',
                eyebrow: 'Part 3',
                mark: _mark('part3.affected-classes', 'Affected classes'),
                rows: const [
                  (
                    'BSCpE 3',
                    'Data & Digital · 7:00 AM – 12:00 NN · '
                        'Engr. Glazen Perez',
                  ),
                  (
                    'BSCpE 4',
                    'Cpe 402 · 10:00 AM – 12:00 NN · '
                        'Engr. Rowell Demdam',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.print_outlined,
                text:
                    'Marks stay in the app. The printed form carries the '
                    'agreed version, with the nine signature slots empty '
                    'for signing by hand.',
              ),
            ],
          ),
        );
      },
    );
  }

  void _finish(int open) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          open == 0
              ? 'Sent on. In the real flow this moves to the next reviewer.'
              : 'Returned with $open change(s) for the proposer to make.',
        ),
      ),
    );
  }
}

/// One part of the form, read-only, with its mark in the margin.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.eyebrow,
    required this.mark,
    required this.rows,
  });

  final String title;
  final String eyebrow;
  final Widget mark;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MonoLabel(eyebrow),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              mark,
            ],
          ),
          const SizedBox(height: 12),
          for (final (label, value) in rows) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 104, child: MonoLabel(label)),
                  Expanded(child: Text(value, style: AppText.caption)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
