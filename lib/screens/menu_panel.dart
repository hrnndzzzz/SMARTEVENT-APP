import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_areas.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'search_screen.dart';

/// The menu, one swipe right of the dashboard.
///
/// Full-width bands rather than a grid of cards: there is no hierarchy
/// to express here, just a list of places, and a band gives the name room
/// to be read at a glance while the colour does the finding.
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
        if (area.id != 'search') area,
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MonoLabel('Menu'),
                        SizedBox(height: 2),
                        Text('Everywhere else', style: AppText.titleBig),
                      ],
                    ),
                  ),
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
                        'Find an event or a transaction',
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
              child: ListView.builder(
                padding: EdgeInsets.only(
                  bottom:
                      MediaQuery.viewPaddingOf(context).bottom +
                      AppLayout.section,
                ),
                itemCount: areas.length,
                itemBuilder: (context, i) =>
                    _Band(area: areas[i], index: i + 1, app: app),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.area, required this.index, required this.app});

  final AppArea area;
  final int index;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final count = area.badge?.call(app);
    // The bands take the page's own surface and the numeral carries the
    // colour, alternating blue and orange down the list. Six full-width
    // fills were six things shouting at once; one accent the size of a
    // coin is enough to make the list read as a set.
    final fill = context.palette.surface;
    final on = context.foregroundOn(fill);
    final accent = index.isOdd
        ? BrutTone.brand.fill(context)
        : BrutTone.orange.fill(context);
    final onAccent = context.foregroundOn(accent);

    return GestureDetector(
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: area.builder)),
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: area.title,
        button: true,
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            // A rule above the first as well, so the top band sits on
            // something instead of floating under the search bar.
            border: Border(
              top: index == 1 ? context.side : BorderSide.none,
              bottom: context.side,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppLayout.gutter,
            18,
            AppLayout.gutter,
            18,
          ),
          child: Row(
            children: [
              // The number is the position in the list, which is the one
              // thing about a band that is true regardless of role.
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.ink, width: 2),
                ),
                child: Text(
                  '$index',
                  style: AppText.number.copyWith(fontSize: 12, color: onAccent),
                ),
              ),
              const SizedBox(width: AppLayout.between),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      area.title,
                      style: AppText.display.copyWith(
                        fontSize: 26,
                        color: on,
                        height: 1.05,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      area.blurb,
                      style: AppText.caption.copyWith(color: on),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppLayout.tight),
              if (count != null && count > 0) ...[
                Text(
                  '$count',
                  style: AppText.moneyLarge.copyWith(fontSize: 22, color: on),
                ),
                const SizedBox(width: AppLayout.between),
              ],
              Icon(Icons.arrow_outward, size: 22, color: on),
            ],
          ),
        ),
      ),
    );
  }
}
