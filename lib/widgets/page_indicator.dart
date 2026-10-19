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
/// It is an indicator first and a control second. The destination you are
/// on is filled with the department's own colour — so the answer to
/// "which way is the menu" is on screen rather than something you have to
/// remember.
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

  /// The three destinations, in order. Icons rather than bars: at this
  /// height a word alone is a small target, and the glyph names the place
  /// faster than the label does.
  static const List<IconData> _icons = [
    Icons.grid_view_rounded,
    Icons.space_dashboard_outlined,
    Icons.calendar_today_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;

    // A raised surface in both themes: white on a light page, the dark
    // theme's own card colour on a dark one. The page itself is slightly
    // off-white and slightly off-black respectively, so the bar reads as
    // lifted without having to be the opposite colour of everything
    // around it.
    final bar = context.palette.surface;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppLayout.gutter,
        AppLayout.tight,
        AppLayout.gutter,
        // Clear of the gesture bar, with a little air of its own.
        (inset > 0 ? inset : AppLayout.tight) + 6,
      ),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: bar,
          borderRadius: BorderRadius.circular(14),
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
    // The department's own colour — blue for most, orange for CITE — which
    // is how the rest of the app shows which organisation you are in.
    final chosen = Theme.of(context).colorScheme.secondary;

    // Measured against whatever each sits on, so neither theme lands on
    // grey over grey.
    final resting = context.foregroundOn(bar).withValues(alpha: 0.55);
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
            padding: EdgeInsets.symmetric(
              horizontal: active ? 11 : 9,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: active ? chosen : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            // The name rides beside the icon on the chosen one only.
            // Three labels stacked under three icons spends most of the
            // bar's height repeating what the icons already say.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: active ? onChosen : resting),
                if (active) ...[
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: AppText.monoLabel.copyWith(
                        fontSize: 9,
                        color: onChosen,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
