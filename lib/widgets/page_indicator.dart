import 'package:flutter/material.dart';

import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';

/// Where you are among the three screens, and a way to get to the other
/// two without swiping.
///
/// It is an indicator first and a control second. Three segments, the
/// one you are on filled — so the answer to "which way is the menu" is
/// on screen rather than something you have to remember.
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

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppLayout.gutter,
        AppLayout.tight,
        AppLayout.gutter,
        (inset > AppLayout.tight ? inset : AppLayout.tight),
      ),
      decoration: BoxDecoration(
        color: context.palette.canvas,
        border: context.borderTop,
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Expanded(
              child: _Segment(
                label: labels[i],
                active: i == current,
                onTap: () => onGo(i),
              ),
            ),
            if (i != labels.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: label,
        selected: active,
        button: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The bar carries the state; the word only names it.
            AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppMotion.press,
              height: 8,
              decoration: BoxDecoration(
                color: active
                    ? Theme.of(context).colorScheme.secondary
                    : context.palette.line,
                borderRadius: AppRadius.pill,
                border: Border.fromBorderSide(context.side),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.monoLabel.copyWith(
                fontSize: 9,
                color: active ? context.palette.ink : context.palette.subtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
