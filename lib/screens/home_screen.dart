import 'dart:math' as math;

import 'package:flutter/material.dart';
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
import '../widgets/budget_peek.dart';
import '../widgets/event_progress_bar.dart';
import '../widgets/floating_peek.dart';
import '../widgets/report_charts.dart';
import '../widgets/report_tiles.dart';
import 'event_detail_screen.dart';
import 'events_screen.dart';
import 'expenses_screen.dart';
import '../theme/peso.dart';
import '../theme/module_identity.dart';

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

    // The same scope Analytics shows, so a tap opens the same figures.
    final charts = ReportChart.all(
      app.financialReport,
      dashboard: app.reportOrganizationId == null
          ? app.dashboard
          : app.organizationDashboard,
      summary: app.proposalSummary,
    );
    final picked = context.watch<AppSettings>().dashboardChart;
    final chart = charts.firstWhere(
      (c) => c.title == picked,
      orElse: () => charts.first,
    );

    return BrutScreen(
      onRefresh: app.refreshAll,
      topBar: AppHeader(),
      // Fixed, not scrolling. Everything here is meant to be taken in
      // at a glance, and a dashboard you have to scroll has already
      // failed at that. What used to be below the fold is either gone
      // or behind a hold now, and the chart takes whatever is left.
      scrollable: false,
      // The record button is docked above the navigation bar by the
      // shell now, so this screen no longer reserves room for a button
      // floating over its own content.
      bottomPadding: AppLayout.section,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.section),
          // One line, not two. "Good afternoon," above the name took a
          // third of the height above the fold to say nothing the
          // second line did not.
          Text(
            '${_greeting(now.hour)}, $name.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.display.copyWith(fontSize: 24, height: 1.1),
          ),
          const SizedBox(height: 2),

          // The date and the scope, on one row rather than one above
          // and one below the greeting.
          //
          // Both open something — the planner and the account — and
          // both were small grey captions that looked like decoration,
          // so both carry a chevron and a tap target. Three stacked
          // rows of header meant the thing the app is actually about
          // started a fifth of the way down the screen.
          //
          // A Wrap rather than a Row: on a narrow phone, or with a long
          // organization name, the two drop onto separate lines instead
          // of one of them being clipped.
          Wrap(
            spacing: AppLayout.between,
            children: [
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
                    // The calendar is a ListView, which wants all the
                    // height there is; the sheet sizes itself to its
                    // content, which offers none. Unbounded inside a
                    // sheet means nothing renders at all, so it is
                    // given most of the screen and scrolls inside that.
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
              if (AppHeader.scopeLineFor(app) case final scope?)
                _HeaderLine(
                  label: scope,
                  icon: Icons.badge_outlined,
                  onTap: () => AccountMenu.show(context),
                ),
            ],
          ),
          const SizedBox(height: AppLayout.between),

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
          //
          // stretch, not the Row default: centre leaves a shorter card
          // floating in the middle of its row with a gap top and
          // bottom. Reserving the bar's space above makes the two the
          // same height anyway; this keeps them that way if one of them
          // ever grows a line the other has not got.
          //
          // IntrinsicHeight because stretch alone is illegal here: the
          // Row's height comes from its tallest child, and stretch asks
          // the children to fill a height that is still being measured.
          // Two children, so the extra pass costs nothing worth saving.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Module.events.icon,
                    accent: Module.events.colorIn(context),
                    // How many exist is a figure nobody acts on, and
                    // it was the first thing on the dashboard. What is
                    // waiting on a decision is the same module's
                    // number, about the same events, that somebody can
                    // do something with.
                    value:
                        '${app.events.where((e) => e.status.isPending).length}',
                    label: 'Events waiting',
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
                    icon: Module.money.icon,
                    accent: Module.money.colorIn(context),
                    value: peso(remaining, decimals: 0),
                    label: 'of ${peso(allocated, decimals: 0)} left',
                    peekTitle: 'Budget',
                    opens: 'money',
                    // The bar fills with what has been spent while the
                    // figure counts what is left, so the tile says how
                    // much remains and shows how far in you are at once.
                    fill: used,
                    // Held, it breaks into categories — the same shape
                    // the events peek takes, so a hold reads the same
                    // way wherever it is done.
                    peekChild: BudgetPeek(categories: app.categories),
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
          ),
          const SizedBox(height: AppLayout.between),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.fact_check_outlined,
                    value: '${app.pendingExpenses.length}',
                    label: 'Awaiting review',
                    opens: 'expenses',
                    accent: Module.money.colorIn(context),
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
                    icon: Module.inventory.icon,
                    value: '${app.dashboard?.lowStockItemCount ?? 0}',
                    label: 'Low stock',
                    opens: 'inventory',
                    accent: Module.inventory.colorIn(context),
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
          ),

          // ── Your events ──────────────────────────────────────────
          // No heading of its own: EventProgressList draws one, with a
          // count and a collapse, and a second one above it said the
          // same thing twice.
          // The list that used to sit here is gone. Holding the
          // Events tile shows all of it, which is what it was for, and
          // the Events tab is one tap away.
          // ── Analytics ────────────────────────────────────────────
          // One of Analytics' own charts, whichever was picked with
          // Change, so the dashboard and Analytics never draw the same
          // figures two different ways.
          if (app.financialReport != null || app.dashboard != null) ...[
            // A section gap, which this heading never had: it sat
            // directly on the tile row above and its text overlapped
            // the cards' drop shadow. Every other block on this screen
            // is separated, and a heading needs more room than the
            // gap between two tiles, not less.
            const SizedBox(height: AppLayout.section),
            BrutSectionTitle(
              'Analytics',
              aside: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SeeAll(
                    label: 'Change',
                    onTap: () => _pickChart(context, charts, chart.title),
                  ),
                  _SeeAll(onTap: () => _open(context, 'reports')),
                ],
              ),
            ),
            const SizedBox(height: AppLayout.tight),
            // Whatever is left over, so the page ends exactly at the
            // bottom instead of running past it.
            Expanded(
              child: ReportChartTile(chart: chart, height: null, width: 360),
            ),
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
    this.accent = AppColors.brand,
    this.peekTitle,
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

  /// 0 to 1, drawn as a bar under the figure, so a tile about a
  /// proportion shows it rather than printing it twice. Null on a tile
  /// that counts things rather than measuring one against a total.
  final double? fill;

  /// Shown in the peek instead of [peek], when the honest answer is a
  /// picture rather than a sentence.
  final Widget? peekChild;

  /// What the peek calls itself, when the tile's label does not read
  /// as a heading on its own. "of P50,000 left" names the figure
  /// beside it, not the panel.
  final String? peekTitle;

  /// Blue or orange, the department's two. Events and money are the
  /// brand's; the two that are asking for something are orange, so the
  /// grid splits into "here is where you stand" and "here is what
  /// wants doing" without a word being added.
  final Color accent;

  void _showPeek(BuildContext context) => showFloatingPeek(
    context,
    title: peekTitle ?? label,
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // A solid block, not a 16% wash of the accent. On the old
              // near-white canvas the wash read as a tint; on cream it
              // read as nothing, and the brighter module colours made
              // it worse rather than better.
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.fromBorderSide(context.side),
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color: context.foregroundOn(accent),
                ),
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
            style: AppText.caption.copyWith(color: p.muted),
          ),
          // A bar, not a wash behind the card. Filling the box read as
          // a stray block with hard edges — worse in dark, where the
          // tint went muddy brown — and it had to dodge the icon. A
          // bar says the same thing in the shape people already read
          // proportions in.
          //
          // The room for it is reserved on every tile, drawn or not.
          // Only the budget has a proportion to show, so it was 19px
          // taller than the other three: the grid came out at three
          // different heights and the short tile in its row floated
          // centred, with a gap above and below. Reserving the space
          // costs the three tiles nothing and makes the four identical
          // without a hardcoded height anywhere.
          const SizedBox(height: 10),
          SizedBox(
            height: BrutProgressBar.thickness,
            child: amount == null
                ? null
                : BrutProgressBar(
                    value: amount.clamp(0.0, 1.0),
                    tone: switch (amount) {
                      >= 1 => BrutTone.coral,
                      >= 0.9 => BrutTone.sun,
                      _ => BrutTone.orange,
                    },
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
  const _SeeAll({required this.onTap, this.label = 'See all'});

  final VoidCallback onTap;
  final String label;

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
              label,
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
    // One full turn of the ring.
    duration: const Duration(seconds: 5),
  )..repeat();

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
    final stage = EventStage.of(event.status);

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
          // The border carries it, not the fill: a card washed in
          // gradient fights the text on it, and an edge that moves
          // draws the eye just as well.
          //
          // The ring both spins and breathes. Spinning alone reads as
          // a loading spinner; breathing alone reads as a warning
          // light. Together they read as something coming up.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _drift,
                builder: (context, _) {
                  final turn = still ? 0.0 : _drift.value * 2 * math.pi;
                  // Out of phase with the turn, so the brightest moment
                  // is not always in the same corner.
                  final breath = still
                      ? 0.75
                      : 0.55 + 0.45 * (0.5 + 0.5 * math.sin(turn * 2));
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.cardAll,
                      gradient: SweepGradient(
                        // A sweep, not a linear one: a linear gradient
                        // can only slide, and an edge that slides off
                        // one side reads as broken rather than turning.
                        transform: GradientRotation(turn),
                        colors: [
                          AppColors.brand.withValues(alpha: breath),
                          AppColors.orange.withValues(alpha: breath),
                          AppColors.brand.withValues(alpha: breath),
                          AppColors.orange.withValues(alpha: breath),
                          AppColors.brand.withValues(alpha: breath),
                        ],
                      ),
                    ),
                    // Punches the middle out, leaving the gradient as a
                    // ring. Cheaper and sharper than two stacked cards.
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.palette.surface,
                          borderRadius: BorderRadius.circular(
                            AppRadius.card - 3,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "In 4 days" sits on the eyebrow rather than in a
                // column of its own down the right-hand side. It is
                // three words; giving them their own column took a
                // third of the card's width away from the two lines
                // that have something to say.
                Row(
                  children: [
                    const MonoLabel('Next up'),
                    const Spacer(),
                    Text(when, style: AppText.number.copyWith(fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.titleBig.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 8),
                // Where it has got to, not only when it is.
                //
                // A date without an approval stage is half the fact: an
                // event in four days that is still with the Dean cannot
                // be spent against, and this card used to show the four
                // days and say nothing about the Dean. The same words
                // the events list and the proposal bar use, from the
                // same place, so the three cannot drift apart.
                Row(
                  children: [
                    BrutBadge(label: stage.label, tone: stage.tone),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stage.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Which Analytics chart the dashboard shows. Kept on this phone.
void _pickChart(
  BuildContext context,
  List<ReportChart> charts,
  String current,
) {
  BrutSheet.show<void>(
    context,
    builder: (sheetContext) => BrutSheet(
      title: 'Dashboard chart',
      subtitle: 'Pick the Analytics chart to show on the dashboard.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in charts) ...[
            BrutListRow(
              title: c.title,
              trailing: c.title == current
                  ? const Icon(Icons.check, size: 18)
                  : null,
              onTap: () {
                context.read<AppSettings>().setDashboardChart(c.title);
                Navigator.of(sheetContext).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
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
      // Sized to its own content. Without the factor an Align fills
      // whatever width it is offered, so two of these in a Wrap each
      // took a full row and the Wrap never had the chance to put them
      // side by side.
      widthFactor: 1,
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
