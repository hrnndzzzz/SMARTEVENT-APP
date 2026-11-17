import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// Which page of a screen you are reading, as one divided block.
///
/// Deliberately not a row of [BrutChip]s. A chip is a thing you switch
/// on and off, and screens that put a chip bar of filters above a chip
/// row of pages ended up with two identical-looking rows doing entirely
/// different jobs — the first narrowing what is counted, the second
/// changing what is shown. One shape cannot carry both without the eye
/// reading them as one list of six filters.
///
/// So this is one surface with hard divisions and a filled segment:
/// closer to a tab bar, which is the thing it actually is.
class SegmentedSwitch<T> extends StatelessWidget {
  const SegmentedSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.segments,
  });

  final T value;
  final ValueChanged<T> onChanged;

  /// In order, left to right.
  final List<(T, String)> segments;

  @override
  Widget build(BuildContext context) {
    final chosen = Theme.of(context).colorScheme.secondary;
    final p = context.palette;

    return BrutSurface(
      fill: p.surface,
      radius: AppRadius.controlAll,
      shadow: AppShadows.sm,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadius.controlAll,
        child: Row(
          children: [
            for (final (index, (key, label)) in segments.indexed) ...[
              if (index > 0)
                // The division, drawn once between each pair rather
                // than as a border on every segment — two adjacent
                // borders read as one thick smudge.
                SizedBox(
                  width: context.side.width,
                  child: ColoredBox(
                    color: context.side.color,
                    child: const SizedBox(height: 40),
                  ),
                ),
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(key),
                  behavior: HitTestBehavior.opaque,
                  child: Semantics(
                    label: label,
                    selected: key == value,
                    button: true,
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      color: key == value ? chosen : null,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.buttonLabel.copyWith(
                          fontSize: 12,
                          // Measured against whatever this segment is
                          // filled with, not taken from the page.
                          color: key == value
                              ? context.foregroundOn(chosen)
                              : p.subtle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
