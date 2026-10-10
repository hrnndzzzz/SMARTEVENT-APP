import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_areas.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import '../widgets/app_header.dart';
import 'notifications_screen.dart';

/// The home screen: who you are, what needs you, and where things live.
///
/// It used to be a wall — five charts, a reports block and a recent
/// activity list, under a six-tab bar, beside a radial menu that repeated
/// every tab and added five more. Everything was one tap away and nothing
/// was findable.
///
/// Now it answers three questions in order: who am I signed in as, what
/// needs doing right now, and where is everything else. The charts and
/// the review queues did not go anywhere — they are the Dashboard area,
/// one card away, which is where someone goes when they want to look at
/// charts rather than be shown them on arrival.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final areas = areasFor(app.currentRole);
    final name = app.currentAccount?.name.split(' ').first ?? 'there';

    return BrutScreen(
      topBar: AppHeader(
        onBellTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        ),
      ),
      // The dock floats over this, so the last row needs room to clear it.
      bottomPadding: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.section),
          Text('Hello, $name.', style: AppText.display),
          const SizedBox(height: 6),
          Text(
            app.currentRole?.responsibility ?? 'Signed in.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppLayout.section),
          const _UpNext(),
          const SizedBox(height: AppLayout.section),
          const BrutSectionTitle('Areas'),
          const SizedBox(height: AppLayout.between),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppLayout.between;
              final width = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final area in areas)
                    SizedBox(
                      width: width,
                      child: _AreaCard(area: area, app: app),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The one to three things actually waiting on this account.
///
/// Only things this role can act on, and only when there are any — an
/// empty "up next" is noise, so it says the useful thing instead.
class _UpNext extends StatelessWidget {
  const _UpNext();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final role = app.currentRole;
    final items = <({String label, String where, BrutTone tone})>[];

    if (role?.canReview ?? false) {
      final events = app.events.where((e) => e.status.isPending).length;
      if (events > 0) {
        items.add((
          label: '$events event${events == 1 ? '' : 's'} awaiting a decision',
          where: 'events',
          tone: BrutTone.sun,
        ));
      }
      final expenses = app.pendingExpenses.length;
      if (expenses > 0) {
        items.add((
          label: '$expenses expense${expenses == 1 ? '' : 's'} to review',
          where: 'money',
          tone: BrutTone.sun,
        ));
      }
    }

    final flagged = app.flaggedExpenses.length;
    if (flagged > 0) {
      items.add((
        label: '$flagged flagged for a second look',
        where: 'risk',
        tone: BrutTone.coral,
      ));
    }

    final low = app.catalog.where((i) => i.isLowStock).length;
    if (low > 0) {
      items.add((
        label: '$low item${low == 1 ? '' : 's'} low on stock',
        where: 'inventory',
        tone: BrutTone.sun,
      ));
    }

    if (items.isEmpty) {
      return BrutCard(
        tone: BrutTone.mint,
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 22),
            const SizedBox(width: AppLayout.between),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Nothing waiting on you',
                    style: AppText.cardTitle.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'This is the normal state, not an empty database.',
                    style: AppText.caption.copyWith(color: AppColorsOn.ink),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrutSectionTitle('Up next'),
          const SizedBox(height: AppLayout.between),
          for (var i = 0; i < items.take(3).length; i++) ...[
            BrutListRow(
              title: items[i].label,
              marker: BrutIconTile(
                icon: Icons.arrow_forward,
                tone: items[i].tone,
                size: 30,
              ),
              onTap: () {
                final area = areaById(items[i].where);
                if (area != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: area.builder),
                  );
                }
              },
            ),
            if (i != items.take(3).length - 1)
              const SizedBox(height: AppLayout.tight),
          ],
        ],
      ),
    );
  }
}

/// A folder card: a tab across the top, an icon tile, the count, the
/// name. Holding one peeks at what it holds without leaving home.
class _AreaCard extends StatelessWidget {
  const _AreaCard({required this.area, required this.app});

  final AppArea area;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final count = area.badge?.call(app);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The tab. It reads as a folder, which is what the card is.
        Container(
          margin: const EdgeInsets.only(left: 10),
          width: 64,
          height: 14,
          decoration: BoxDecoration(
            color: area.tone.fill(context),
            border: context.borderAll,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(6),
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -2),
          child: BrutCard(
            padding: const EdgeInsets.all(12),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: area.builder)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    BrutIconTile(icon: area.icon, tone: area.tone, size: 40),
                    const Spacer(),
                    if (count != null && count > 0)
                      BrutBadge(
                        label: '$count',
                        tone: area.tone,
                        mono: true,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  area.title,
                  style: AppText.cardTitle.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  area.blurb,
                  style: AppText.caption.copyWith(fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Ink on a filled card, whatever the theme.
abstract final class AppColorsOn {
  static const Color ink = Color(0xFF1A1A1A);
}
