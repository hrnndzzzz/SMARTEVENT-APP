import 'package:flutter/material.dart';

import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';

/// Where you are among the three screens, and a way to get to the other
/// two without swiping.
///
/// A floating bar rather than a full-width strip: it reads as a control
/// sitting above the page instead of a border the page ends at, and the
/// gap underneath keeps it clear of the phone's own gesture bar.
///
/// It is an indicator first and a control second. The segment you are on
/// is filled — so the answer to "which way is the menu" is on screen
/// rather than something you have to remember.
class PageIndicator extends StatelessWidget {
  const PageIndicator({
    super.key,
    required this.current,
    required this.onGo,
    required this.labels,
  });

  /// Index of the page being shown.
  final int current;
  final ValueChanged<int> onGo;
  final List<String> labels;

  /// The three destinations, in order. Icons rather than bars now: at this
  /// size a word alone is a small target, and the glyph names the place
  /// faster than the label does.
  static const List<IconData> _icons = [
    Icons.grid_view_rounded,
    Icons.space_dashboard_outlined,
    Icons.calendar_today_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    final palette = context.palette;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppLayout.gutter,
        AppLayout.tight,
        AppLayout.gutter,
        // Clear of the gesture bar, with a little air of its own.
        (inset > 0 ? inset : AppLayout.tight) + 6,
      ),
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: palette.ink,
          borderRadius: BorderRadius.circular(18),
          border: Border.fromBorderSide(context.side),
          boxShadow: AppShadows.base,
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: _Segment(
                  label: labels[i],
                  icon: _icons[i % _icons.length],
                  active: i == current,
                  onTap: () => onGo(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Everything sits on the dark bar, so the resting colour is the
    // canvas rather than the ink — the usual pairing is inverted here.
    final resting = palette.canvas.withValues(alpha: 0.55);
    final chosen = Theme.of(context).colorScheme.secondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: label,
        selected: active,
        button: true,
        child: Center(
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppMotion.press,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? chosen : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: active ? palette.ink : resting,
                ),
                const SizedBox(height: 3),
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.monoLabel.copyWith(
                    fontSize: 9,
                    color: active ? palette.ink : resting,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
