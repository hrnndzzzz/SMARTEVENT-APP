import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/activity_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// "Last change · Maria Santos removed Batteries · 2026-11-08 15:40".
///
/// [area] is `proposals`, `inventory` or `finance`; [entityId] narrows it to
/// one record. Shows nothing until there is something to say, and nothing
/// in the demo or offline.
///
/// shortcut: refetches after this app's own writes and on open, so another
/// member's change shows the next time the screen opens; poll if that is
/// too slow.
class LastChangeNote extends StatefulWidget {
  const LastChangeNote({super.key, required this.area, this.entityId});

  final String area;
  final String? entityId;

  @override
  State<LastChangeNote> createState() => _LastChangeNoteState();
}

class _LastChangeNoteState extends State<LastChangeNote> {
  ActivityNote? _note;
  int? _seenWrites;

  Future<void> _load() async {
    if (!mounted) return;
    final note = await context.read<AppState>().lastChange(
      widget.area,
      entityId: widget.entityId,
    );
    if (mounted) setState(() => _note = note);
  }

  @override
  Widget build(BuildContext context) {
    final int writes;
    try {
      writes = context.select<AppState, int>((app) => app.writeCount);
    } on ProviderNotFoundException {
      // A screen shown on its own, as in a widget test, has no app state to
      // ask, and a courtesy line must not be what brings the screen down.
      return const SizedBox.shrink();
    }
    if (writes != _seenWrites) {
      _seenWrites = writes;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final note = _note;
    if (note == null) return const SizedBox.shrink();
    final at = note.createdAt.toLocal();
    final time =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return Text(
      'Last change · ${note.sentence} · ${BrutDateField.format(at)} $time',
      style: AppText.caption,
    );
  }
}
