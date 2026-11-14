import 'package:flutter/material.dart';

import '../state/sap_notes.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// The margin of the paper form, as a control.
///
/// Sits beside a field or a section and shows what a reviewer wrote
/// against it: a tick for read-and-fine, a note, or a change that has to
/// happen first. Tapping opens the thread and adds to it.
///
/// Deliberately small and quiet when there is nothing to say. An
/// un-marked form should look like a form, not like a review tool.
class SapNoteMark extends StatelessWidget {
  const SapNoteMark({
    super.key,
    required this.notes,
    required this.anchor,
    required this.title,
    required this.author,
    required this.authorRole,
    this.canReview = true,
  });

  final SapNotes notes;

  /// What this mark is attached to, e.g. `part3.affected-classes`.
  final String anchor;

  /// What the thread is about, shown as the sheet's heading.
  final String title;

  /// Who a new mark would be from.
  final String author;
  final String authorRole;

  /// Whether this account may add marks. A proposer reading their own
  /// returned form can see every note and resolve them, which is the
  /// point, but should not be annotating it as a reviewer.
  final bool canReview;

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NoteSheet(
        notes: notes,
        anchor: anchor,
        title: title,
        author: author,
        authorRole: authorRole,
        canReview: canReview,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: notes,
      builder: (context, _) {
        final mine = notes.on(anchor);
        final needsChange = notes.hasUnresolvedChange(anchor);
        final palette = context.palette;

        final (fill, glyph) = switch ((mine.isEmpty, needsChange)) {
          (true, _) => (palette.surface, '+'),
          (false, true) => (BrutTone.coral.fill(context), '!'),
          (false, false) => (BrutTone.mint.fill(context), '✓'),
        };

        return Semantics(
          button: true,
          label: mine.isEmpty
              ? 'Add a note on $title'
              : '${mine.length} note(s) on $title',
          child: GestureDetector(
            onTap: () => _open(context),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: AppRadius.pill,
                border: Border.fromBorderSide(context.side),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    glyph,
                    style: AppText.monoLabel.copyWith(
                      fontSize: 11,
                      color: context.foregroundOn(fill),
                    ),
                  ),
                  if (mine.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Text(
                      '${mine.length}',
                      style: AppText.monoLabel.copyWith(
                        fontSize: 10,
                        color: context.foregroundOn(fill),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({
    required this.notes,
    required this.anchor,
    required this.title,
    required this.author,
    required this.authorRole,
    required this.canReview,
  });

  final SapNotes notes;
  final String anchor;
  final String title;
  final String author;
  final String authorRole;
  final bool canReview;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _text = TextEditingController();
  SapNoteKind _kind = SapNoteKind.note;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    // A tick says everything by itself; the other two do not.
    if (_kind != SapNoteKind.checked && _text.text.trim().isEmpty) return;
    await widget.notes.add(
      anchor: widget.anchor,
      kind: _kind,
      author: widget.author,
      authorRole: widget.authorRole,
      text: _text.text,
    );
    _text.clear();
    if (mounted) setState(() => _kind = SapNoteKind.note);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.notes,
      builder: (context, _) {
        final thread = widget.notes.on(widget.anchor);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BrutSectionTitle(widget.title),
                const SizedBox(height: 10),

                if (thread.isEmpty)
                  const BrutInlineMessage(
                    tone: BrutTone.neutral,
                    icon: Icons.edit_note,
                    text: 'Nothing written here yet.',
                  ),
                for (final note in thread) ...[
                  _NoteRow(
                    note: note,
                    onToggle: () =>
                        widget.notes.setResolved(note.id, !note.resolved),
                  ),
                  const SizedBox(height: 8),
                ],

                if (widget.canReview) ...[
                  const SizedBox(height: 10),
                  const BrutSectionTitle('Add a mark'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final kind in SapNoteKind.values)
                        IntrinsicWidth(
                          child: BrutChip(
                            label: kind.label,
                            selected: _kind == kind,
                            tone: switch (kind) {
                              SapNoteKind.checked => BrutTone.mint,
                              SapNoteKind.change => BrutTone.coral,
                              SapNoteKind.note => BrutTone.brand,
                            },
                            onTap: () => setState(() => _kind = kind),
                          ),
                        ),
                    ],
                  ),
                  if (_kind != SapNoteKind.checked) ...[
                    const SizedBox(height: 12),
                    BrutTextField(
                      controller: _text,
                      label: 'What to say',
                      hint: _kind == SapNoteKind.change
                          ? 'Move it to the afternoon; morning classes clash.'
                          : 'Noted.',
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 14),
                  BrutButton(
                    label: _kind == SapNoteKind.checked
                        ? 'Mark as checked'
                        : 'Add it',
                    onPressed:
                        _kind == SapNoteKind.checked ||
                            _text.text.trim().isNotEmpty
                        ? _add
                        : null,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.onToggle});

  final SapNote note;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tone = switch (note.kind) {
      SapNoteKind.checked => BrutTone.mint,
      SapNoteKind.change => BrutTone.coral,
      SapNoteKind.note => BrutTone.neutral,
    };

    return BrutCard(
      tone: note.resolved ? BrutTone.neutral : tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${note.author} · ${note.authorRole}',
                  style: AppText.monoLabel.copyWith(fontSize: 9),
                ),
              ),
              Text(
                _when(note.at),
                style: AppText.monoLabel.copyWith(fontSize: 9),
              ),
            ],
          ),
          if (note.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note.text, style: AppText.body),
          ] else ...[
            const SizedBox(height: 6),
            Text(note.kind.label, style: AppText.body),
          ],
          if (note.kind == SapNoteKind.change) ...[
            const SizedBox(height: 10),
            BrutButton(
              label: note.resolved ? 'Reopen' : 'Mark as done',
              size: BrutSize.small,
              tone: BrutTone.neutral,
              onPressed: onToggle,
            ),
          ],
        ],
      ),
    );
  }

  static String _when(DateTime at) =>
      '${at.day}/${at.month} ${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}
