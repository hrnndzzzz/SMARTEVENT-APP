import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_areas.dart';
import '../state/app_settings.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'search_screen.dart';
import '../theme/module_identity.dart';

/// The menu, one swipe right of the dashboard.
///
/// A grid of blocks that fills the screen, each in its module's own
/// colour.
///
/// It was a list of full-width bands on the page's surface, with the
/// colour reduced to a coin beside each name. The argument for that was
/// that there is no hierarchy here, only places — which is true, and
/// which a grid says just as well. What it did not survive was the
/// count: four places make four rows, and four rows leave most of a
/// phone empty. The review said so in one word.
///
/// Filling the colour rather than coining it also makes this screen
/// agree with the one it opens: tap the purple block, land on a purple
/// band.
///
/// Dashboard and Events are not on it. They are the two screens either
/// side of this one, and a menu entry that takes you where a swipe
/// already takes you is the duplication that made the old app a pile.
class MenuPanel extends StatelessWidget {
  const MenuPanel({super.key, this.onClose});

  /// Returns to the dashboard. Null when the panel is a page in a swipe
  /// view that handles its own back gesture.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final areas = [
      for (final area in menuAreasFor(app.currentRole))
        if (area.id != 'search' &&
            !(app.isOfflineViewing && area.id == 'admin'))
          area,
    ];

    return Scaffold(
      backgroundColor: context.palette.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppLayout.gutter,
                AppLayout.contentPadding,
                AppLayout.gutter,
                AppLayout.between,
              ),
              child: Row(
                children: [
                  // Just the word, at page size. "Everywhere else" under
                  // a MENU eyebrow was two labels for one screen, and
                  // the screen is plainly the menu.
                  const Expanded(child: Text('Menu', style: AppText.display)),
                  if (onClose != null)
                    BrutIconButton(
                      icon: Icons.close,
                      label: 'Back to the dashboard',
                      onPressed: onClose,
                    ),
                ],
              ),
            ),
            // Search sits above the list rather than inside it: it is not
            // a seventh place to go, it is how you skip going to any of
            // them. Tapping opens the screen with the keyboard already up.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppLayout.gutter,
                0,
                AppLayout.gutter,
                AppLayout.between,
              ),
              child: BrutSurface(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SearchScreen(autofocus: true),
                  ),
                ),
                semanticLabel: 'Search events and transactions',
                radius: AppRadius.controlAll,
                shadow: AppShadows.sm,
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: context.palette.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Find anything, or ask where something is',
                        style: AppText.body.copyWith(
                          color: context.palette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppLayout.gutter,
                  0,
                  AppLayout.gutter,
                  MediaQuery.viewPaddingOf(context).bottom + AppLayout.tight,
                ),
                child: _Grid(areas: areas, app: app),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two across, filling whatever height the screen has left.
///
/// Expanded rows rather than a fixed cell height: a menu that stops
/// two thirds of the way down is the thing this replaced, and a phone
/// is not one height. An odd last block takes the full width instead of
/// leaving a hole — unlike a grid of figures, where a double-width cell
/// would read as the important one, the last place is a place like the
/// others and the row is the bottom of the screen.
class _Grid extends StatelessWidget {
  const _Grid({required this.areas, required this.app});

  final List<AppArea> areas;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < areas.length; i += 2) {
      final left = areas[i];
      final right = i + 1 < areas.length ? areas[i + 1] : null;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _Block(area: left, app: app)),
              if (right != null) ...[
                const SizedBox(width: 10),
                Expanded(child: _Block(area: right, app: app)),
              ],
            ],
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.area, required this.app});

  final AppArea area;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final count = area.badge?.call(app);
    // The module's own colour, filled. It used to be a coin beside the
    // name on a surface-coloured band, which made the menu and the
    // screen it opens disagree about what colour that place is.
    final fill =
        moduleForAreaId(area.id)?.colorIn(context) ?? context.palette.muted;
    final on = context.foregroundOn(fill);

    return BrutSurface(
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: area.builder)),
      semanticLabel: area.title,
      fill: fill,
      radius: AppRadius.cardAll,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Punched out of the fill rather than drawn on it, the
              // same way the band at the top of each module carries its
              // icon, so the two read as the same object.
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: on.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(area.icon, size: 22, color: on),
              ),
              const Spacer(),
              if (count != null && count > 0)
                _WaitingCount(count: count, label: area.badgeLabel, ring: on),
            ],
          ),
          const Spacer(),
          // The arrow rides the title, not the blurb. Beside the blurb
          // it took 24pt off a line of body text, which is a word and a
          // half at this width: on a 360pt phone every blurb in the
          // grid ended in an ellipsis while the title beside the arrow
          // had room to spare.
          Row(
            children: [
              // Scaled down rather than clipped. "Inventory" at 22pt
              // does not fit a half-width block on a 360pt phone, and
              // the name of the place is the one thing on this screen
              // that must survive — an ellipsis in the middle of it is
              // worse than a point or two of type.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    area.title,
                    style: AppText.display.copyWith(
                      fontSize: 22,
                      color: on,
                      height: 1.05,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_outward, size: 18, color: on),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            area.blurb,
            style: AppText.caption.copyWith(
              color: on.withValues(alpha: 0.75),
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// A block with something waiting behind it, said in a figure that
/// breathes.
///
/// One swell every ten seconds: long enough apart that six of them are
/// not a light show, bright enough that the eye catches one while
/// reading something else.
///
/// It was a red gradient down the band's right edge, which worked while
/// every band was the page's own cream. On a block filled with the
/// module's colour a red edge is invisible against Flagged's red and
/// fights everything else, so the same ten-second swell moves to the
/// count itself — which carries on any fill, and says how many as well
/// as that there are some.
class _WaitingCount extends StatefulWidget {
  const _WaitingCount({
    required this.count,
    required this.label,
    required this.ring,
  });

  final int count;
  final String? label;

  /// The block's own foreground. The pill's outline was hardcoded ink,
  /// which is a black ring on a black-inked block: invisible on
  /// Flagged's dark red, where the signal matters most, and muddy on
  /// Money's orange, which is coral's near neighbour. Taking the
  /// block's foreground means it separates from every fill by
  /// construction rather than by luck.
  final Color ring;

  @override
  State<_WaitingCount> createState() => _WaitingCountState();
}

class _WaitingCountState extends State<_WaitingCount>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var still = MediaQuery.disableAnimationsOf(context);
    try {
      still = still || context.watch<AppSettings>().reduceMotion;
    } on ProviderNotFoundException {
      // A test host without the settings provider still gets a count.
    }

    final fill = BrutTone.coral.fill(context);
    final on = context.foregroundOn(fill);

    Widget pill(double strength) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: widget.ring, width: 2),
        // The swell, not a colour change: the pill is already the red
        // that means "this wants you" everywhere else in the app, and a
        // red that brightens and dims is a different red.
        boxShadow: strength <= 0
            ? null
            : [
                BoxShadow(
                  color: fill.withValues(alpha: 0.75 * strength),
                  blurRadius: 14 * strength,
                  spreadRadius: 3 * strength,
                ),
              ],
      ),
      child: Text(
        '${widget.count}',
        style: AppText.number.copyWith(fontSize: 12, color: on),
      ),
    );

    final semantic = '${widget.count} ${widget.label ?? 'waiting'}';

    // Held steady rather than removed: the signal is the point, the
    // movement is only what makes it noticed.
    if (still) return Semantics(label: semantic, child: pill(0.4));

    return Semantics(
      label: semantic,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // One swell inside the first fifth of the cycle, flat after.
          final t = _controller.value;
          return pill(t < 0.2 ? math.sin(t / 0.2 * math.pi) : 0.0);
        },
      ),
    );
  }
}
