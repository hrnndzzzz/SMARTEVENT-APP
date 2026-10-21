import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/brut.dart';

/// Small pieces the six part screens share.
///
/// The paper form is mostly tick boxes, and a tick box that allows one
/// answer is a different control from one that allows several. Keeping
/// both here stops each part screen reinventing them, and keeps the
/// wording of "choose one" against "choose any" consistent.

/// A labelled group where exactly one option may be chosen.
class SapSingleChoice<T> extends StatelessWidget {
  const SapSingleChoice({
    super.key,
    required this.label,
    required this.options,
    required this.labelOf,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final List<T> options;
  final String Function(T) labelOf;
  final T? value;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppText.monoLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              IntrinsicWidth(
                child: BrutChip(
                  label: labelOf(option),
                  selected: option == value,
                // Tapping the chosen one again clears it, because the
                // paper lets you leave a row blank and the form should
                // not trap someone into an answer they cannot undo.
                  onTap: !enabled
                      ? () {}
                      : () => onChanged(option == value ? null : option),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A labelled group where any number of options may be chosen.
class SapMultiChoice<T> extends StatelessWidget {
  const SapMultiChoice({
    super.key,
    required this.label,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final List<T> options;
  final String Function(T) labelOf;
  final List<T> selected;
  final ValueChanged<List<T>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppText.monoLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              IntrinsicWidth(
                child: BrutChip(
                  label: labelOf(option),
                  selected: selected.contains(option),
                  onTap: !enabled
                      ? () {}
                      : () {
                          final next = [...selected];
                          selected.contains(option)
                              ? next.remove(option)
                              : next.add(option);
                          onChanged(next);
                        },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A time of day, picked rather than typed.
///
/// Times go to the server as local Asia/Manila `HH:MM:SS` with no offset,
/// so this deliberately never touches [DateTime] — converting through one
/// would attach a timezone the form does not have.
class SapTimeField extends StatelessWidget {
  const SapTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final SapTime? value;
  final ValueChanged<SapTime> onChanged;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final initial = value ?? const SapTime(8, 0);
    final chosen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (chosen != null) onChanged(SapTime(chosen.hour, chosen.minute));
  }

  @override
  Widget build(BuildContext context) {
    // Mirrors BrutDateField's shape; that widget takes a DateTime and a
    // time of day is deliberately not one here, since converting through
    // one would attach a timezone the form does not carry.
    final shown = value?.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MonoLabel(label),
        const SizedBox(height: 6),
        BrutSurface(
          onTap: enabled ? () => _pick(context) : null,
          radius: AppRadius.controlAll,
          shadow: AppShadows.sm,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  shown ?? 'Pick a time',
                  style: shown == null
                      ? AppText.body.copyWith(color: context.palette.muted)
                      : AppText.number,
                ),
              ),
              const Icon(Icons.schedule, size: 16),
            ],
          ),
        ),
      ],
    );
  }
}

/// A row of a repeating table, with a delete affordance.
///
/// Every collection on this form is replaced wholesale by the API, so
/// these edit a local list that the screen then sends in full.
class SapRowCard extends StatelessWidget {
  const SapRowCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onRemove,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BrutListRow(
      title: title,
      meta: subtitle,
      onTap: onTap,
      trailing: onRemove == null
          ? null
          : BrutIconButton(
              icon: Icons.close,
              label: 'Remove $title',
              onPressed: onRemove,
            ),
    );
  }
}

/// The banner Parts 4 to 6 carry, mirroring the red note on the paper.
class SapSdsOnlyNotice extends StatelessWidget {
  const SapSdsOnlyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const BrutInlineMessage(
      tone: BrutTone.sun,
      icon: Icons.admin_panel_settings_outlined,
      text: 'This part is filled in by the SDS Office.',
    );
  }
}
