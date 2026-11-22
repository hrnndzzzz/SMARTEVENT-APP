import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// One stop on the tour: what to light up, and what to say about it.
class TourStep {
  const TourStep(this.target, this.title, this.body);

  final GlobalKey target;
  final String title;
  final String body;
}

/// What the first-sign-in tour points at.
///
/// Static, because the shell builds exactly one dashboard. A second copy
/// of any of these in the tree at once would be a duplicate key.
class TourTargets {
  TourTargets._();

  static final header = GlobalKey(debugLabel: 'tour.header');
  static final date = GlobalKey(debugLabel: 'tour.date');
  static final budget = GlobalKey(debugLabel: 'tour.budget');
  static final record = GlobalKey(debugLabel: 'tour.record');
  static final pages = GlobalKey(debugLabel: 'tour.pages');
}

/// Dims the screen and lights up each step's target in turn, with a card
/// saying what it is. A step whose target is not on screen is left out,
/// which is how a role without a control skips the stop about it.
Future<void> showSpotlightTour(
  BuildContext context,
  List<TourStep> steps,
) async {
  // Whatever is closing above the caller — the sign-in screen, Settings
  // on a replay — still moves what is underneath while it goes, and a
  // hole measured mid-transition would sit beside its target.
  await _settled(ModalRoute.of(context)?.secondaryAnimation);
  if (!context.mounted) return;
  final shown = steps.where((s) => s.target.currentContext != null).toList();
  if (shown.isEmpty) return;
  final still = MediaQuery.disableAnimationsOf(context);
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: still ? Duration.zero : AppMotion.sheet,
      reverseTransitionDuration: still ? Duration.zero : AppMotion.sheet,
      pageBuilder: (_, _, _) => _Tour(steps: shown),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

Future<void> _settled(Animation<double>? animation) {
  if (animation == null || animation.isDismissed) return Future.value();
  final done = Completer<void>();
  void check(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    animation.removeStatusListener(check);
    done.complete();
  }

  animation.addStatusListener(check);
  return done.future;
}

class _Tour extends StatefulWidget {
  const _Tour({required this.steps});

  final List<TourStep> steps;

  @override
  State<_Tour> createState() => _TourState();
}

class _TourState extends State<_Tour> {
  int _index = 0;
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus());
  }

  Future<void> _focus() async {
    final target = widget.steps[_index].target.currentContext;
    if (target != null && target.mounted) {
      // Only when it is not already in view, so the dashboard does not
      // jump about between stops that are all on screen.
      await Scrollable.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.sheet,
      );
    }
    if (!mounted) return;
    final box = widget.steps[_index].target.currentContext?.findRenderObject();
    final self = context.findRenderObject();
    if (box is! RenderBox || !box.attached || self is! RenderBox) {
      // The control went away while the tour was up. Move on.
      return _next();
    }
    // Global on both sides: the banners and the phone-width column sit
    // around the navigator, so the tour's origin is not the screen's.
    final origin = self.localToGlobal(Offset.zero);
    setState(() => _hole = (box.localToGlobal(Offset.zero) - origin) & box.size);
  }

  void _next() {
    if (_index == widget.steps.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index++);
    _focus();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    final last = _index == widget.steps.length - 1;
    final hole = _hole;
    final inset = MediaQuery.paddingOf(context);

    final card = Semantics(
      liveRegion: true,
      child: BrutCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MonoLabel('${_index + 1} of ${widget.steps.length}'),
            const SizedBox(height: 6),
            Text(step.title, style: AppText.cardTitle),
            const SizedBox(height: 4),
            Text(step.body, style: AppText.body),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!last)
                  BrutButton(
                    label: 'Skip',
                    tone: BrutTone.neutral,
                    size: BrutSize.small,
                    expand: false,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                const Spacer(),
                BrutButton(
                  label: last ? 'Done' : 'Next',
                  trailingIcon: last ? null : Icons.arrow_forward,
                  size: BrutSize.small,
                  expand: false,
                  onPressed: _next,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, box) {
          // The card goes on whichever side of the hole has more room,
          // and is held inside it, so a tall card on a short phone never
          // covers the thing it is talking about.
          final below = hole == null || box.maxHeight - hole.bottom >= hole.top;
          return Stack(
            children: [
              // Swallows every tap, so nothing under the dark is pressed
              // by accident. Next and Skip are the only ways on.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CustomPaint(painter: _Scrim(hole)),
                ),
              ),
              if (hole != null)
                Positioned(
                  left: AppLayout.gutter,
                  right: AppLayout.gutter,
                  top: below ? hole.bottom + 14 : inset.top + 12,
                  bottom: below
                      ? inset.bottom + 12
                      : box.maxHeight - hole.top + 14,
                  child: Align(
                    alignment: below
                        ? Alignment.topCenter
                        : Alignment.bottomCenter,
                    child: card,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The dark, with a hole cut where the target is and a hard edge round
/// it — the same 2px outline every Brut surface carries.
class _Scrim extends CustomPainter {
  _Scrim(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    final h = hole;
    final cut = h == null
        ? null
        : RRect.fromRectAndRadius(h.inflate(6), const Radius.circular(14));
    if (cut != null) dark.addRRect(cut);
    canvas.drawPath(dark, Paint()..color = Colors.black.withValues(alpha: 0.72));
    if (cut != null) {
      canvas.drawRRect(
        cut,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_Scrim old) => old.hole != hole;
}
