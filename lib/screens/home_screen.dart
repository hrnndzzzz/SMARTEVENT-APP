import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_areas.dart';
import '../state/app_settings.dart';
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
import '../widgets/floating_peek.dart';
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

          // The next activity, first. It is the one thing on this
          // screen with a deadline attached, and it was below the
          // figures where it read as an afterthought.
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

          // Four figures in a grid, then one bar, then the lists.
          //
          // There were nine blocks here: a hero card, four tiles, two
          // stats, a bar and a chart. The people who tried it said the
          // same thing they said about the proposal form — too much
          // happening. These are the four numbers worth opening the app
          // for, and each one is a way into the module behind it.
          //
          // Long-press any of them to look without leaving the page.
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.inventory_2_outlined,
                  value: '${app.events.length}',
                  label: 'Events',
                  opens: 'events',
                  trend: _Trend.up,
                  onTap: () => _open(context, 'events'),
                  peek: _eventsPeek(app),
                  // Not a sentence: the same bars the list below draws,
                  // so a hold answers "where has everything got to?".
                  peekChild: EventProgressPeek(
                    events: app.events,
                    onOpen: (event) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EventDetailScreen(event: event),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppLayout.between),
              Expanded(
                child: _StatTile(
                  icon: Icons.account_balance_wallet_outlined,
                  value: peso(remaining, decimals: 0),
                  label: 'of ${peso(allocated, decimals: 0)} left',
                  opens: 'money',
                  // The box fills as the budget goes, so the tile says
                  // how much is left and shows it at the same time.
                  // The bar that used to do this is gone.
                  fill: used,
                  trend: used >= 0.9 ? _Trend.down : _Trend.up,
                  onTap: () => _open(context, 'money'),
                  peek:
                      '${peso(allocated, decimals: 0)} allocated, '
                      '${peso(spent, decimals: 0)} approved.\n'
                      '${(used * 100).round()}% of the budget is used.',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.between),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.fact_check_outlined,
                  value: '${app.pendingExpenses.length}',
                  label: 'Awaiting review',
                  opens: 'expenses',
                  trend: app.pendingExpenses.isEmpty
                      ? _Trend.flat
                      : _Trend.down,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ExpensesScreen()),
                  ),
                  peek: app.pendingExpenses.isEmpty
                      ? 'Nothing is waiting on a decision.'
                      : '${app.pendingExpenses.length} expense'
                            '${app.pendingExpenses.length == 1 ? '' : 's'} '
                            'waiting on a decision.',
                ),
              ),
              const SizedBox(width: AppLayout.between),
              Expanded(
                child: _StatTile(
                  icon: Icons.warehouse_outlined,
                  value: '${app.dashboard?.lowStockItemCount ?? 0}',
                  label: 'Low stock',
                  opens: 'inventory',
                  trend: (app.dashboard?.lowStockItemCount ?? 0) == 0
                      ? _Trend.flat
                      : _Trend.down,
                  onTap: () => _open(context, 'inventory'),
                  peek: app.dashboard == null
                      ? 'The figures have not loaded yet.'
                      : '${app.dashboard!.lowStockItemCount} item(s) at or '
                            'below their threshold, '
                            '${app.dashboard!.draftInventoryCount} draft '
                            'waiting to be confirmed.',
                ),
              ),
            ],
          ),

          // ── Your events ──────────────────────────────────────────
          // No heading of its own: EventProgressList draws one, with a
          // count and a collapse, and a second one above it said the
          // same thing twice.
          EventProgressList(
            events: app.events,
            onOpen: (event) => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EventDetailScreen(event: event),
              ),
            ),
          ),
          const SizedBox(height: AppLayout.section),

          // ── Analytics ────────────────────────────────────────────
          // The chart only. The three counts it used to sit under are
          // in the grid at the top now.
          if (app.spendingTrends.length > 1) ...[
            BrutSectionTitle(
              'Analytics',
              aside: _SeeAll(onTap: () => _open(context, 'reports')),
            ),
            const SizedBox(height: AppLayout.between),
            _SpendingTrend(points: app.spendingTrends),
            const SizedBox(height: AppLayout.section),
          ],
        ],
      ),
    );
  }

  /// What the Events tile says when it is held.
  static String _eventsPeek(AppState app) {
    if (app.events.isEmpty) return 'No events on record yet.';
    final waiting = app.events.where((e) => e.status.isPending).length;
    final next = _nextEvent(app);
    return [
      '${app.events.length} on record, $waiting waiting on a decision.',
      if (next != null) 'Next up: ${next.title}.',
    ].join('\n');
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

/// Which way a figure is going, for the badge beside it.
enum _Trend { up, down, flat }

/// One figure, as a square.
///
/// Icon, the number, where it is heading, and what it is — in that
/// order, because the number is what the eye is looking for and the
/// label only matters once it has found it.
///
/// Tapping opens the module. Holding shows [peek]: enough to answer
/// "should I go there?" without going there, which is the whole reason
/// for a dashboard.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.trend,
    required this.onTap,
    required this.peek,
    required this.opens,
    this.fill,
    this.peekChild,
  });

  final IconData icon;
  final String value;
  final String label;
  final _Trend trend;
  final VoidCallback onTap;
  final String peek;

  /// Where tapping goes, for the peek's button. The tile's own label
  /// names a figure, not a place: "Open Left to spend" is not English.
  final String opens;

  /// 0 to 1. Fills the card behind the figure by that much, so a tile
  /// about a proportion shows it rather than printing it twice.
  final double? fill;

  /// Shown in the peek instead of [peek], when the honest answer is a
  /// picture rather than a sentence.
  final Widget? peekChild;

  void _showPeek(BuildContext context) => showFloatingPeek(
    context,
    title: label,
    subtitle: value,
    openLabel: 'Open $opens',
    onOpen: onTap,
    child: peekChild ?? Text(peek, style: AppText.body),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final amount = fill;
    return BrutCard(
      onTap: onTap,
      onLongPress: () => _showPeek(context),
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          if (amount != null)
            // Rises from the bottom as the budget goes. Orange while
            // there is room, coral once there is not — the same two
            // tones the bar it replaces used.
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.bottomCenter,
                heightFactor: amount.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: amount >= 1 ? p.coralTint : p.orangeTint,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: p.brandTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 17, color: p.ink),
                    ),
                    const Spacer(),
                    _TrendBadge(trend: trend),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: AppText.heroNumber.copyWith(fontSize: 26),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Full ink where a fill sits behind it: muted grey
                  // on the orange was legible but only just, and this
                  // label carries the other half of the figure above.
                  style: AppText.caption.copyWith(
                    color: amount == null ? p.muted : p.ink,
                    fontWeight: amount == null ? null : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The small round arrow beside a figure.
class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});

  final _Trend trend;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, fill) = switch (trend) {
      _Trend.up => (Icons.trending_up, p.mintTint),
      _Trend.down => (Icons.trending_down, p.coralTint),
      // Nothing to report is not good news or bad: a flat dash in the
      // neutral tint, rather than a green arrow saying all is well.
      _Trend.flat => (Icons.trending_flat, p.line),
    };
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Icon(icon, size: 14, color: p.ink),
    );
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
/// The next activity, at the top, with the light moving across it.
///
/// Everything else on this screen is a standing figure. This one has a
/// date coming, so it is the only thing here that moves: a slow drift
/// between the brand blue and the department orange, which says "this
/// one is live" without a badge shouting it.
class _NextUp extends StatefulWidget {
  const _NextUp({required this.event, required this.onTap});

  final EventItem event;
  final VoidCallback onTap;

  @override
  State<_NextUp> createState() => _NextUpState();
}

class _NextUpState extends State<_NextUp> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    // Slow on purpose. Fast enough to notice on a second glance,
    // slow enough that nobody watching a demo finds it distracting.
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final onTap = widget.onTap;
    final today = DateUtils.dateOnly(DateTime.now());
    final days = DateUtils.dateOnly(event.on!).difference(today).inDays;
    final when = switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => 'In $days days',
    };

    // Reduce-motion holds it still rather than removing the colour:
    // the gradient is what marks this card out, the movement is only
    // how it draws the eye.
    var still = MediaQuery.disableAnimationsOf(context);
    try {
      still = still || context.watch<AppSettings>().reduceMotion;
    } on ProviderNotFoundException {
      // A test host without the settings provider still gets a card.
    }

    return BrutCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Inside the card rather than behind it, so it takes the
          // card's own corners and sits under its border.
          Positioned.fill(
            child: ClipRRect(
              borderRadius: AppRadius.cardAll,
              child: AnimatedBuilder(
                animation: _drift,
                builder: (context, _) {
                  final t = still ? 0.5 : _drift.value;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        // The ends travel rather than the colours
                        // changing, so it reads as light moving across
                        // the card rather than the card changing colour.
                        begin: Alignment(-1 - t, -1),
                        end: Alignment(1 + t, 1),
                        colors: const [AppColors.brand, AppColors.orange],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
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
          ),
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
