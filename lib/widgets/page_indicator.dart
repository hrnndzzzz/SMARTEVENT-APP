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

    // The bar is the darkest thing on a light page and a raised surface
    // on a dark one. Using the ink colour for both would paint it nearly
    // white in the dark theme, where ink is #F2F1EC — a white slab where
    // a floating control should be.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bar = dark ? palette.surface : palette.ink;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppLayout.gutter,
        AppLayout.tight,
        AppLayout.gutter,
        // Clear of the gesture bar, with a little air of its own.
        (inset > 0 ? inset : AppLayout.tight) + 6,
      ),
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: bar,
          borderRadius: BorderRadius.circular(16),
          border: Border.fromBorderSide(context.side),
          boxShadow: AppShadows.sm,
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: _Segment(
                  label: labels[i],
                  icon: _icons[i % _icons.length],
                  active: i == current,
                  bar: bar,
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
    required this.bar,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;

  /// What this sits on, so the foreground can be measured against it
  /// rather than assumed.
  final Color bar;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chosen = Theme.of(context).colorScheme.secondary;

    // Measured against whatever the bar turned out to be, so neither
    // theme ends up with grey-on-grey.
    final resting = context.foregroundOn(bar).withValues(alpha: 0.6);
    final onChosen = context.foregroundOn(chosen);

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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: active ? chosen : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: active ? onChosen : resting),
                const SizedBox(height: 2),
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.monoLabel.copyWith(
                    fontSize: 8,
                    color: active ? onChosen : resting,
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
