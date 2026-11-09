import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_areas.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import '../widgets/account_menu.dart';
import '../widgets/event_calendar.dart';
import '../widgets/app_header.dart';
import '../widgets/event_progress_bar.dart';
import 'event_detail_screen.dart';
import 'events_screen.dart';
import 'expenses_screen.dart';
import '../theme/peso.dart';

/// The dashboard: where you stand, what needs you, and the one thing you
/// are most likely to have opened the app to do.
///
/// Laid out in the three parts the app is actually made of — Events,
/// Finance, Analytics — each under its own heading. Before, the money
/// figures ran straight on from the event list with nothing between
/// them, so the page read as one undifferentiated column and the only
/// way to know which module a figure belonged to was to recognise it.
///
/// Analytics sits last on purpose. Someone who wants to study a chart
/// goes looking for it; someone opening the app at a supplier's counter
/// does not.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  static String _greeting(int hour) => switch (hour) {
    < 12 => 'Good morning',
    < 18 => 'Good afternoon',
    _ => 'Good evening',
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = DateTime.now();
    final name = app.currentAccount?.name.split(' ').first ?? 'there';

    final allocated = app.totalAllocated;
    final remaining = app.remainingBalance;
    final spent = app.totalExpended;
    final used = allocated == 0 ? 0.0 : (spent / allocated).clamp(0.0, 1.0);

    return BrutScreen(
      onRefresh: app.refreshAll,
      topBar: AppHeader(),
      // The record button is docked above the navigation bar by the
      // shell now, so this screen no longer reserves room for a button
      // floating over its own content.
      bottomPadding: AppLayout.section,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.section),
          // The date opens the planner and the scope line opens the
          // account: both were small grey captions that looked like
          // decoration, so both now carry a chevron and a tap target.
          _HeaderLine(
            label:
                '${_days[now.weekday - 1]} / ${_months[now.month - 1]} '
                '${now.day}',
            icon: Icons.calendar_month_outlined,
            onTap: () => BrutSheet.show<void>(
              context,
              builder: (sheetContext) => BrutSheet(
                title: 'Planner',
                subtitle: 'Everything with a date on it.',
                // The calendar is a ListView, which wants all the height
                // there is; the sheet sizes itself to its content, which
                // offers none. Unbounded inside a sheet means nothing
                // renders at all, so it is given most of the screen and
                // scrolls inside that.
                child: SizedBox(
                  height: MediaQuery.sizeOf(sheetContext).height * 0.62,
                  child: EventCalendar(
                    events: app.events,
                    onOpen: (event) {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EventDetailScreen(event: event),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_greeting(now.hour)},\n$name.',
            style: AppText.display.copyWith(height: 1.1),
          ),
          if (AppHeader.scopeLineFor(app) case final scope?) ...[
            const SizedBox(height: 6),
            _HeaderLine(
              label: scope,
              icon: Icons.badge_outlined,
              onTap: () => AccountMenu.show(context),
            ),
          ],
          const SizedBox(height: AppLayout.section),

          // ── Events ────────────────────────────────────────────────
          // First under the greeting, because "has my event moved?" is
          // the first question anyone opening this app has. What needs
          // attention now lives on the bell, where the count already was.
          BrutSectionTitle(
            'Events',
            aside: _SeeAll(onTap: () => _open(context, 'events')),
          ),
          const SizedBox(height: AppLayout.between),
          if (_nextEvent(app) case final next?) ...[
            _NextUp(
              event: next,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventDetailScreen(event: next),
                ),
              ),
            ),
            const SizedBox(height: AppLayout.between),
          ],
          EventProgressList(
            events: app.events,
            onOpen: (event) => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EventDetailScreen(event: event),
              ),
            ),
          ),
          const SizedBox(height: AppLayout.section),

          // ── Finance ───────────────────────────────────────────────
          BrutSectionTitle(
            'Finance',
            aside: _SeeAll(onTap: () => _open(context, 'money')),
          ),
          const SizedBox(height: AppLayout.between),

          // The hero: what is left, beside the two numbers that explain it.
          //
          // No fixed height. It used to be pinned at 168, which fitted at
          // 100% text and overflowed by three pixels on a phone with
          // larger system type — a bug nobody sees until it is on someone
          // else's device. IntrinsicHeight lets the tiles size themselves
          // and the card match them.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: BrutCard(
                    onTap: () => _open(context, 'money'),
                    // Blue, not black. The figure people open the app for
                    // should wear one of the department's two colours
                    // rather than a neutral that belongs to neither.
                    tone: BrutTone.brand,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${peso(remaining, decimals: 0)}',
                            style: AppText.heroNumber.copyWith(fontSize: 40),
                          ),
                        ),
                        const SizedBox(height: AppLayout.section),
                        const MonoLabel('Remaining budget'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppLayout.between),
                Expanded(
                  flex: 2,
                  // One tile standing beside the card, so it takes the
                  // card's height rather than shrinking to its own text
                  // and leaving the pair looking mismatched.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Tile(
                          value: '${app.pendingExpenses.length}',
                          label: 'Awaiting review',
                          tone: app.pendingExpenses.isEmpty
                              ? BrutTone.neutral
                              : BrutTone.orange,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ExpensesScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.between),

          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: '${peso(allocated, decimals: 0)}',
                  label: 'Allocated',
                  onTap: () => _open(context, 'money'),
                ),
              ),
              const SizedBox(width: AppLayout.between),
              Expanded(
                child: _Stat(
                  value: '${peso(spent, decimals: 0)}',
                  label: 'Approved spending',
                  onTap: () => _open(context, 'money'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.between),

          BrutCard(
            onTap: () => _open(context, 'money'),
            radius: AppRadius.rowAll,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: MonoLabel('Budget used')),
                    Text(
                      '${(used * 100).round()}%',
                      style: AppText.number.copyWith(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                BrutProgressBar(
                  value: used,
                  tone: used >= 1 ? BrutTone.coral : BrutTone.orange,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.section),

          // ── Analytics ─────────────────────────────────────────────
          // What the server has already counted. Shown only when it has
          // been loaded: three zeroes while a request is in flight read
          // as "nothing is wrong", which is the one thing this section
          // must never say by accident.
          if (app.dashboard case final summary?) ...[
            BrutSectionTitle(
              'Analytics',
              aside: _SeeAll(onTap: () => _open(context, 'reports')),
            ),
            const SizedBox(height: AppLayout.between),
            Row(
              children: [
                Expanded(
                  child: _Tile(
                    value: '${summary.flaggedExpenseCount}',
                    label: 'Flagged',
                    tone: summary.flaggedExpenseCount == 0
                        ? BrutTone.neutral
                        : BrutTone.coral,
                    onTap: () => _open(context, 'reports'),
                  ),
                ),
                const SizedBox(width: AppLayout.between),
                Expanded(
                  child: _Tile(
                    value: '${summary.lowStockItemCount}',
                    label: 'Low stock',
                    tone: summary.lowStockItemCount == 0
                        ? BrutTone.neutral
                        : BrutTone.orange,
                    onTap: () => _open(context, 'inventory'),
                  ),
                ),
                const SizedBox(width: AppLayout.between),
                Expanded(
                  child: _Tile(
                    value: '${summary.draftInventoryCount}',
                    label: 'Draft items',
                    tone: summary.draftInventoryCount == 0
                        ? BrutTone.neutral
                        : BrutTone.neutral,
                    onTap: () => _open(context, 'inventory'),
                  ),
                ),
              ],
            ),
            if (app.spendingTrends.length > 1) ...[
              const SizedBox(height: AppLayout.between),
              _SpendingTrend(points: app.spendingTrends),
            ],
            const SizedBox(height: AppLayout.section),
          ],
        ],
      ),
    );
  }

  /// The soonest event still ahead of us, or null when there is none.
  /// Rejected and completed ones are behind us whatever their date says.
  static EventItem? _nextEvent(AppState app) {
    final now = DateTime.now();
    // A date is optional on an event, and one without a date cannot be
    // the next thing happening.
    final ahead =
        app.events
            .where(
              (e) =>
                  e.on != null &&
                  e.on!.isAfter(now) &&
                  e.status != EventApprovalStatus.rejected &&
                  e.status != EventApprovalStatus.completed,
            )
            .toList()
          ..sort((a, b) => a.on!.compareTo(b.on!));
    return ahead.isEmpty ? null : ahead.first;
  }
}

/// The "see all" affordance on a section heading. A section whose title
/// is not tappable looks like a label; this says the module is there.
class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'See all',
              style: AppText.caption.copyWith(
                color: p.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: p.muted),
          ],
        ),
      ),
    );
  }
}

/// How long until the next activity. Counting in days is what anyone
/// actually asks; a date alone makes them do the subtraction.
class _NextUp extends StatelessWidget {
  const _NextUp({required this.event, required this.onTap});

  final EventItem event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final days = DateUtils.dateOnly(event.on!).difference(today).inDays;
    final when = switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => 'In $days days',
    };

    return BrutCard(
      onTap: onTap,
      tone: days <= 1 ? BrutTone.orange : BrutTone.neutral,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MonoLabel('Next up'),
                const SizedBox(height: 6),
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.titleBig.copyWith(fontSize: 17),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(when, style: AppText.number.copyWith(fontSize: 14)),
        ],
      ),
    );
  }
}

/// Six months of spending as bars. Deliberately not a charting library:
/// the shape is the whole message, and the figures are a tap away in
/// Reports for anyone who wants them.
class _SpendingTrend extends StatelessWidget {
  const _SpendingTrend({required this.points});

  final List<SpendingTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final peak = points.fold<double>(
      0,
      (most, point) => point.totalAmount > most ? point.totalAmount : most,
    );

    return BrutCard(
      radius: AppRadius.rowAll,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MonoLabel('Spending, last 6 months'),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in points) ...[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Expanded first: a FractionallySizedBox needs a
                        // bounded height to take a fraction of, and a
                        // Column hands its children unbounded height.
                        Expanded(
                          child: FractionallySizedBox(
                            alignment: Alignment.bottomCenter,
                            // A month with nothing spent still gets a
                            // sliver, so the gap reads as zero rather
                            // than as missing.
                            heightFactor: peak == 0
                                ? 0.04
                                : (point.totalAmount / peak).clamp(0.04, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: point == points.last
                                    ? p.brandTint
                                    : p.muted.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          point.month.substring(5),
                          style: AppText.caption.copyWith(
                            fontSize: 9,
                            color: p.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (point != points.last) const SizedBox(width: 5),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.value,
    required this.label,
    required this.tone,
    this.onTap,
  });

  final String value;
  final String label;
  final BrutTone tone;

  /// Where the figure came from. A number with no way through to the
  /// records behind it is a dead end on the screen people open most.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      onTap: onTap,
      tone: tone,
      radius: AppRadius.rowAll,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.moneyLarge.copyWith(fontSize: 24),
            ),
          ),
          const SizedBox(height: 6),
          MonoLabel(label, fontSize: 9),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      onTap: onTap,
      radius: AppRadius.rowAll,
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.moneyLarge.copyWith(fontSize: 19),
            ),
          ),
          const SizedBox(height: 4),
          MonoLabel(label, fontSize: 9),
        ],
      ),
    );
  }
}

/// Where an alert row goes when tapped.
///
/// Most rows name an area, but the two review queues are screens inside
/// one — Money owns expenses, Events owns approvals — so they are named
/// directly rather than being given an area each.
void _open(BuildContext context, String where) {
  final WidgetBuilder? builder = switch (where) {
    'expenses' => (_) => const ExpensesScreen(),
    'events' => (_) => const EventsScreen(),
    _ => areaById(where)?.builder,
  };
  if (builder != null) {
    Navigator.of(context).push(MaterialPageRoute(builder: builder));
  }
}

/// What is actually waiting on this account, and nothing else.
///
/// Only things this role can act on, and only when there are any — an
/// empty alert is noise, so it says the useful thing instead.
class AlertWidget extends StatelessWidget {
  const AlertWidget({super.key});

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
          tone: BrutTone.coral,
        ));
      }
      final expenses = app.pendingExpenses.length;
      if (expenses > 0) {
        items.add((
          label: '$expenses expense${expenses == 1 ? '' : 's'} to review',
          where: 'expenses',
          tone: BrutTone.coral,
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
        tone: BrutTone.coral,
      ));
    }

    if (items.isEmpty) {
      return BrutCard(
        tone: BrutTone.mint,
        radius: AppRadius.rowAll,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 20),
            const SizedBox(width: AppLayout.between),
            Expanded(
              child: Text(
                'Nothing waiting on you.',
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final shown = items.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutFoldable(
          title: 'Needs you',
          count: items.length,
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              BrutListRow(
                title: shown[i].label,
                marker: BrutIconTile(
                  icon: Icons.priority_high,
                  tone: shown[i].tone,
                  size: 32,
                ),
                onTap: () => _open(context, shown[i].where),
              ),
              if (i != shown.length - 1)
                const SizedBox(height: AppLayout.tight),
            ],
          ],
        ),
      ],
    );
  }
}

/// One of the two lines framing the greeting.
///
/// Both used to be plain mono captions, which read as decoration and
/// hid what they lead to: the date opens the planner, the scope line
/// opens the account. Bigger, with an icon and a chevron, and a tap
/// target tall enough for a thumb.
class _HeaderLine extends StatelessWidget {
  const _HeaderLine({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.palette.ink;

    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: ink),
              const SizedBox(width: 6),
              MonoLabel(label, fontSize: 13, color: ink),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 16, color: ink),
            ],
          ),
        ),
      ),
    );
  }
}
