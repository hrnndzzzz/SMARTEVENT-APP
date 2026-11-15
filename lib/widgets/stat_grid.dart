import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// Four figures, as a 2×2 block.
///
/// Money grew this shape first — allocated, spent, left, pending — and
/// it is the thing people said worked: four numbers you can take in
/// without reading a word, each coloured by what it is saying. The
/// other module front pages went straight from their coloured band into
/// a list, so they opened on a screen that had told you nothing yet.
///
/// It lives here rather than on Money because three screens were about
/// to grow three slightly different versions of it, and a grid whose
/// cell padding differs by two pixels between modules is exactly the
/// kind of thing nobody sees one screen at a time and everybody sees
/// flipping between them.
///
/// Give it two cells or four. Anything else is a list.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.cells});

  final List<StatCell> cells;

  @override
  Widget build(BuildContext context) {
    final rows = (cells.length / 2).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < rows; row++) ...[
          // IntrinsicHeight, because stretching a Row's children needs a
          // height to stretch to and this sits in a scrollable, where
          // there is none. Without it the row cannot lay out and the
          // screen comes up with the first two figures and nothing else.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cells[row * 2]),
                const SizedBox(width: 10),
                // An odd number of cells leaves a hole rather than a
                // double-width cell: the grid is a grid, and one cell
                // twice the size of its neighbours reads as the
                // important one when it is only the last one.
                Expanded(
                  child: row * 2 + 1 < cells.length
                      ? cells[row * 2 + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          if (row < rows - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// One of the four.
class StatCell extends StatelessWidget {
  const StatCell({
    super.key,
    required this.label,
    required this.value,
    required this.tone,
    this.onTap,
    this.hint,
  });

  final String label;
  final String value;
  final BrutTone tone;
  final VoidCallback? onTap;

  /// A second line, when the figure needs one.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: tone,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: MonoLabel(label, fontSize: 10)),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 16, color: context.palette.ink),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppText.moneyLarge.copyWith(fontSize: 22),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hint case final line?) ...[
            const SizedBox(height: 4),
            Text(line, style: AppText.caption.copyWith(fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
