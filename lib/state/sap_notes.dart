import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The green pen, digitised.
///
/// A reviewed proposal comes back covered in marks: ticks beside the
/// budget lines that were checked, "Noted" in the diverse-needs box, and
/// a note in the margin under the affected classes asking whether the
/// activity could move to the afternoon. All of it is attached to a
/// particular part of the form, not to the form as a whole.
///
/// The backend has no place for this. It can return a whole proposal
/// with one comment, which is the blunt version of the same idea, so
/// these live on the device until there is somewhere to put them. That
/// is enough to show the shape of it and to run a review end to end.
enum SapNoteKind {
  /// A tick: this part was read and is fine. The commonest mark on the
  /// paper by a wide margin.
  checked('Checked', '✓'),

  /// A remark that does not block anything.
  note('Note', '✎'),

  /// Something that has to change before this can go further.
  change('Needs a change', '!');

  const SapNoteKind(this.label, this.glyph);

  final String label;
  final String glyph;

  static SapNoteKind fromName(String? v) {
    for (final k in SapNoteKind.values) {
      if (k.name == v) return k;
    }
    return SapNoteKind.note;
  }
}

/// One mark, against one part of the form.
@immutable
class SapNote {
  const SapNote({
    required this.id,
    required this.anchor,
    required this.kind,
    required this.author,
    required this.authorRole,
    required this.at,
    this.text = '',
    this.resolved = false,
  });

  final String id;

  /// What it is attached to: `part1.activity_date`, `part3.budget`,
  /// `part3.affected-classes`. Stable strings rather than indices, so a
  /// reordered screen does not move everyone's marks.
  final String anchor;

  final SapNoteKind kind;
  final String author;
  final String authorRole;
  final DateTime at;

  /// Empty for a plain tick, which says everything it needs to.
  final String text;

  /// Ticked off by whoever had to act on it. Kept rather than deleted:
  /// the point of a review trail is that it still exists afterwards.
  final bool resolved;

  SapNote copyWith({bool? resolved}) => SapNote(
    id: id,
    anchor: anchor,
    kind: kind,
    author: author,
    authorRole: authorRole,
    at: at,
    text: text,
    resolved: resolved ?? this.resolved,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'anchor': anchor,
    'kind': kind.name,
    'author': author,
    'author_role': authorRole,
    'at': at.toIso8601String(),
    'text': text,
    'resolved': resolved,
  };

  factory SapNote.fromJson(Map<String, dynamic> json) => SapNote(
    id: json['id'] as String,
    anchor: (json['anchor'] as String?) ?? '',
    kind: SapNoteKind.fromName(json['kind'] as String?),
    author: (json['author'] as String?) ?? '',
    authorRole: (json['author_role'] as String?) ?? '',
    at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime(1970),
    text: (json['text'] as String?) ?? '',
    resolved: (json['resolved'] as bool?) ?? false,
  );
}

/// Every mark on one proposal.
class SapNotes extends ChangeNotifier {
  SapNotes({required this.eventId});

  final String eventId;

  String get _key => 'sap_notes_$eventId';

  final List<SapNote> _notes = [];
  List<SapNote> get all => List.unmodifiable(_notes);

  /// The marks on one part of the form, newest last so a thread reads
  /// top to bottom.
  List<SapNote> on(String anchor) => [
    for (final n in _notes)
      if (n.anchor == anchor) n,
  ]..sort((a, b) => a.at.compareTo(b.at));

  /// What still wants doing: a change that nobody has resolved.
  int get openChangeCount => [
    for (final n in _notes)
      if (n.kind == SapNoteKind.change && !n.resolved) n,
  ].length;

  int get total => _notes.length;

  bool hasUnresolvedChange(String anchor) => _notes.any(
    (n) =>
        n.anchor == anchor && n.kind == SapNoteKind.change && !n.resolved,
  );

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      _notes
        ..clear()
        ..addAll(_decode(raw));
    } catch (_) {
      // An unreadable store is an empty one; the form still works.
    }
    notifyListeners();
  }

  static List<SapNote> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final rows = jsonDecode(raw);
      if (rows is! List) return const [];
      return [
        for (final row in rows)
          SapNote.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([for (final n in _notes) n.toJson()]),
      );
    } catch (_) {
      // Keeping it in memory is better than refusing the mark.
    }
  }

  Future<void> add({
    required String anchor,
    required SapNoteKind kind,
    required String author,
    required String authorRole,
    String text = '',
  }) async {
    _notes.add(
      SapNote(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        anchor: anchor,
        kind: kind,
        author: author,
        authorRole: authorRole,
        at: DateTime.now(),
        text: text.trim(),
      ),
    );
    notifyListeners();
    await _save();
  }

  Future<void> setResolved(String id, bool resolved) async {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    _notes[i] = _notes[i].copyWith(resolved: resolved);
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _notes.removeWhere((n) => n.id == id);
    notifyListeners();
    await _save();
  }

  /// Everything, cleared. For starting a demo from a known state.
  Future<void> clear() async {
    _notes.clear();
    notifyListeners();
    await _save();
  }

  /// The marks on the real approved copy of Hack the Future, so a demo
  /// opens on something recognisable rather than an empty form.
  Future<void> seedFromPaper() async {
    _notes
      ..clear()
      ..addAll([
        SapNote(
          id: 'seed-1',
          anchor: 'part1.core_values',
          kind: SapNoteKind.checked,
          author: 'Engr. Aileen M. Habaradas',
          authorRole: 'Moderator',
          at: DateTime(2026, 9, 29, 10, 12),
        ),
        SapNote(
          id: 'seed-2',
          anchor: 'part1.egas',
          kind: SapNoteKind.checked,
          author: 'Engr. Aileen M. Habaradas',
          authorRole: 'Moderator',
          at: DateTime(2026, 9, 29, 10, 13),
        ),
        SapNote(
          id: 'seed-3',
          anchor: 'part3.budget',
          kind: SapNoteKind.checked,
          author: 'Ms. Le-Mairre M. Tapang',
          authorRole: 'SDS Coordinator',
          at: DateTime(2026, 9, 30, 9, 2),
          text: 'Totals verified against the breakdown.',
        ),
        SapNote(
          id: 'seed-4',
          anchor: 'part2.diverse_needs',
          kind: SapNoteKind.note,
          author: 'Ms. Le-Mairre M. Tapang',
          authorRole: 'SDS Coordinator',
          at: DateTime(2026, 9, 30, 9, 5),
          text: 'Noted.',
        ),
        SapNote(
          id: 'seed-5',
          anchor: 'part3.affected-classes',
          kind: SapNoteKind.change,
          author: 'Engr. Aileen M. Habaradas',
          authorRole: 'Moderator',
          at: DateTime(2026, 9, 30, 9, 18),
          text:
              'Please check if you can move the time in the afternoon if '
              'there are affected classes in the morning.',
        ),
      ]);
    notifyListeners();
    await _save();
  }
}
