import 'package:flutter/material.dart';

import '../theme/app_layout.dart';

/// Places a popover under the control that opened it.
///
/// Both menus in the header used to sit at a fixed top-right corner, so
/// the one opened from the avatar lined up and the one opened from the
/// bell — which is not the rightmost control — did not. A window that
/// points at nothing reads as a dialog rather than as that button's own
/// panel.
///
/// The anchor is the opening control's rect in global coordinates. When
/// it cannot be measured, usually because the control has gone before
/// the route is built, this falls back to the old fixed corner rather
/// than refusing to show anything.
class PopoverFrame extends StatelessWidget {
  const PopoverFrame({super.key, required this.anchor, required this.child});

  final Rect? anchor;
  final Widget child;

  /// Taller than any header control. Past this the rect is not a button
  /// but whatever larger thing the caller's context resolved to.
  static const double _maxAnchorHeight = 120;

  /// Below this there is no point hanging anything underneath.
  static const double _minRoomBelow = 160;

  /// The opening control's rect, for passing to [anchor].
  ///
  /// Call this with the control's own `BuildContext` *before* pushing
  /// the route: afterwards the element may be gone and the render
  /// object with it.
  static Rect? anchorOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    const margin = AppLayout.popoverMargin;

    final room = size.width - margin * 2;
    final width = room < AppLayout.popoverMaxWidth
        ? room
        : AppLayout.popoverMaxWidth;

    // An anchor is only useful if it is plausibly a control and leaves
    // room beneath it. A caller that hands over a screen-sized context
    // gets the whole body back from findRenderObject, and hanging a
    // panel off the bottom of that puts it off the screen.
    final rect = anchor;
    final usable =
        rect != null &&
        rect.height <= _maxAnchorHeight &&
        size.height - rect.bottom >= _minRoomBelow;

    final double top;
    final double left;
    if (!usable) {
      top = AppLayout.popoverTop;
      left = size.width - margin - width;
    } else {
      // Hangs below the control, with its right edge on the control's
      // right edge, so the panel reads as having come out of it.
      top = (rect.bottom + AppLayout.popoverGap).clamp(
        media.padding.top + 4,
        // Guaranteed above the minimum by the usability check.
        size.height - _minRoomBelow,
      );
      // Clamped so a control near either edge still gets a panel that
      // fits, rather than one running off the screen.
      left = (rect.right - width).clamp(
        margin,
        // max is below min on a screen narrower than the panel plus its
        // margins; clamp requires min <= max, so the wider of the two wins.
        (size.width - margin - width).clamp(margin, double.infinity),
      );
    }

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          // Whatever is inside, the panel stops at the bottom margin
          // rather than running off the screen and taking its last rows
          // with it. Anything taller scrolls within its own list.
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: size.height - top - margin),
            child: child,
          ),
        ),
      ],
    );
  }
}
