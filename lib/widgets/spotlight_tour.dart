import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// One stop on the tour: which [TourSpot] to light up, and what to say.
class TourStep {
  const TourStep(this.spot, this.title, this.body);

  final String spot;
  final String title;
  final String body;
}

/// Marks [child] as something the tour can point at, by name.
///
/// A name rather than a GlobalKey: a module screen can be opened from the
/// Menu, a dashboard tile or Search, and two copies holding one static
/// key would be a duplicate-key crash. Several spots may share a name —
/// every card in a list does — and the first one mounted answers.
class TourSpot extends StatefulWidget {
  const TourSpot(this.id, {super.key, required this.child});

  final String id;
  final Widget child;

  static final _live = <String, List<BuildContext>>{};

  /// The first mounted spot called [id], or null.
  static BuildContext? find(String id) => _live[id]?.firstOrNull;

  @override
  State<TourSpot> createState() => _TourSpotState();
}

class _TourSpotState extends State<TourSpot> {
  @override
  void initState() {
    super.initState();
    (TourSpot._live[widget.id] ??= []).add(context);
  }

  @override
  void didUpdateWidget(TourSpot old) {
    super.didUpdateWidget(old);
    if (old.id == widget.id) return;
    TourSpot._live[old.id]?.remove(context);
    (TourSpot._live[widget.id] ??= []).add(context);
  }

  @override
  void dispose() {
    TourSpot._live[widget.id]?.remove(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Dims the screen and lights up each step's spot in turn, with a card
/// saying what it is. A step whose spot is not on screen is left out,
/// which is how a role without a control skips the stop about it.
///
/// [section] names the screen on the card ("Money · 2 of 3"). [more]
/// says another screen follows, so the last button reads Next and Skip
/// stays offered. False only when the person chose to stop, with Skip or
/// Back; a screen with nothing to show counts as carrying on.
Future<bool> showSpotlightTour(
  BuildContext context,
  List<TourStep> steps, {
  String? section,
  bool more = false,
}) async {
  // Ready means a spot has mounted — a screen that opens after a load
  // has not got one yet — and the route above the caller has stopped
  // moving: a hole measured mid-transition sits beside its target.
  // Timers rather than frames, so a screen that never shows up costs
  // three seconds and not a hang.
  final above = ModalRoute.of(context)?.secondaryAnimation;
  for (var i = 0; i < 60; i++) {
    final ready =
        steps.any((s) => TourSpot.find(s.spot) != null) &&
        !(above?.isAnimating ?? false);
    if (ready || !context.mounted) break;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (!context.mounted) return false;
  final shown = steps.where((s) => TourSpot.find(s.spot) != null).toList();
  if (shown.isEmpty) return true;
  final still = MediaQuery.disableAnimationsOf(context);
  final finished = await Navigator.of(context).push<bool>(
    PageRouteBuilder<bool>(
      opaque: false,
      transitionDuration: still ? Duration.zero : AppMotion.sheet,
      reverseTransitionDuration: still ? Duration.zero : AppMotion.sheet,
      pageBuilder: (_, _, _) =>
          _Tour(steps: shown, section: section, more: more),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
  return finished ?? false;
}

class _Tour extends StatefulWidget {
  const _Tour({required this.steps, this.section, this.more = false});

  final List<TourStep> steps;
  final String? section;
  final bool more;

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
    final spot = widget.steps[_index].spot;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.sheet;
    // Only when it is not already in view, so a screen does not jump
    // about between stops that are all on it. Start, then end: one
    // brings back a spot scrolled off the top, the other one below.
    for (final policy in const [
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    ]) {
      final target = TourSpot.find(spot);
      if (target == null || !target.mounted) break;
      await Scrollable.ensureVisible(
        target,
        alignmentPolicy: policy,
        duration: duration,
      );
    }
    if (!mounted) return;
    final box = TourSpot.find(spot)?.findRenderObject();
    final self = context.findRenderObject();
    if (box is! RenderBox || !box.attached || self is! RenderBox) {
      // The control went away while the tour was up. Move on.
      return _next();
    }
    // Global on both sides: the banners and the phone-width column sit
    // around the navigator, so the tour's origin is not the screen's.
    final origin = self.localToGlobal(Offset.zero);
    setState(
      () => _hole = (box.localToGlobal(Offset.zero) - origin) & box.size,
    );
  }

  void _next() {
    if (_index == widget.steps.length - 1) {
      Navigator.of(context).pop(true);
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
            MonoLabel(
              [
                ?widget.section,
                '${_index + 1} of ${widget.steps.length}',
              ].join(' · '),
            ),
            const SizedBox(height: 6),
            Text(step.title, style: AppText.cardTitle),
            const SizedBox(height: 4),
            Text(step.body, style: AppText.body),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!last || widget.more)
                  BrutButton(
                    label: 'Skip',
                    tone: BrutTone.neutral,
                    size: BrutSize.small,
                    expand: false,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                const Spacer(),
                BrutButton(
                  label: last && !widget.more ? 'Done' : 'Next',
                  trailingIcon: last && !widget.more
                      ? null
                      : Icons.arrow_forward,
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
          // A spot that leaves no room either side — the Menu's grid is
          // most of the screen — gets the card over its lower edge
          // instead, since squeezed into the gap it overflows.
          // shortcut: 220 is a guessed card height, measure it if very
          // large text ever needs more.
          final room = hole == null
              ? 0.0
              : below
              ? box.maxHeight - hole.bottom - inset.bottom
              : hole.top - inset.top;
          final cramped = room < 220;
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
              if (hole != null && cramped)
                Positioned(
                  left: AppLayout.gutter,
                  right: AppLayout.gutter,
                  bottom: inset.bottom + 12,
                  child: card,
                )
              else if (hole != null)
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
    canvas.drawPath(
      dark,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );
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
