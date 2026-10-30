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
  /// Where the marker is solid and where it falls away. See
  /// [_Segment._markerForImpl].
  static Gradient markerFor(int position, int count, Color colour) =>
      _Segment._markerForImpl(position, count, colour);

  const PageIndicator({
    super.key,
    required this.current,
    required this.onGo,
    required this.labels,
    this.covered,
  });

  /// Index of the page being shown.
  final int current;
  final ValueChanged<int> onGo;
  final List<String> labels;

  /// A segment with something docked over it — the record button rises
  /// out of the bar and is wider than a label is tall, so the label
  /// underneath peeked out around the circle. The slot keeps its width
  /// so the others stay where they are, and draws nothing: on the one
  /// page this happens, the covered tab is the page you are already on.
  final int? covered;

  /// The three destinations, in order. The glyph names the place; the
  /// word is carried by [Semantics] for anyone who cannot see it.
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
        height: 54,
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
              if (i == covered)
                const Expanded(child: SizedBox.shrink())
              else
                Expanded(
                  child: _Segment(
                    label: labels[i],
                    icon: _icons[i % _icons.length],
                    active: i == current,
                    bar: bar,
                    position: i,
                    count: labels.length,
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
    required this.position,
    required this.count,
    required this.onTap,
  });

  /// Where the marker is solid and where it falls away.
  ///
  /// Solid along the outside edge of the bar and fading towards the
  /// middle: the first destination holds its left, the last holds its
  /// right, and anything between them fades at both ends. It points
  /// outward to the edge you are nearest, instead of sitting as a flat
  /// block that looks the same wherever it lands.
  static Gradient _markerForImpl(int position, int count, Color colour) {
    final soft = colour.withValues(alpha: 0.35);

    if (count <= 1) {
      return LinearGradient(colors: [soft, colour, soft]);
    }
    if (position == 0) {
      return LinearGradient(colors: [colour, soft]);
    }
    if (position == count - 1) {
      return LinearGradient(colors: [soft, colour]);
    }
    return LinearGradient(colors: [soft, colour, soft]);
  }

  final String label;
  final IconData icon;
  final bool active;

  /// What this sits on, so the foreground can be measured against it
  /// rather than assumed.
  final Color bar;

  final int position;
  final int count;

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              gradient: active
                  ? PageIndicator.markerFor(position, count, chosen)
                  : null,
              borderRadius: BorderRadius.circular(10),
            ),
            // The glyph carries the place and the word underneath names
            // it, on every destination rather than only the chosen one —
            // otherwise the two you are not on are the ones left unnamed.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: active ? onChosen : resting),
                const SizedBox(height: 2),
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
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
