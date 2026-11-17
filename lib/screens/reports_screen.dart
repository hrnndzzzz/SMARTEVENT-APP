import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../state/report_insights.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import '../widgets/app_header.dart';
import '../widgets/brut_date_picker.dart';
import '../widgets/module_band.dart';
import '../widgets/segmented_switch.dart';
import '../theme/module_identity.dart';
import '../widgets/report_charts.dart';
import '../widgets/report_status.dart';
import '../widgets/report_tiles.dart';
import '../theme/peso.dart';
import 'event_report_screen.dart';
import 'export_preview_screen.dart';

/// Analytics: where the money came from, where it went, and against what
/// budget, for one period at a time.
///
/// Three things this screen is deliberate about:
///
///  * Every figure is the **server's**, for the filters on screen. Nothing
///    is summed from whatever lists the phone happens to hold, so the
///    charts, the ledger and the printed report always agree.
///  * The **window the backend actually used** is shown, so the figures and
///    the stated range always agree.
///  * An **export uses the filters currently on screen**, so the file
///    cannot disagree with what was read.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _Tab { overview, events, ledger }

class _ReportsScreenState extends State<ReportsScreen> {
  bool _exporting = false;
  _Tab _tab = _Tab.overview;
  LedgerFilter _filter = LedgerFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  /// The report, and the dashboard counts under "Needs a look", for the
  /// same organization.
  Future<void> _reload() async {
    if (!mounted) return;
    final app = context.read<AppState>();
    unawaited(app.loadProposalSummary());
    await Future.wait([
      app.loadFinancialReport(),
      app.reportOrganizationId == null
          ? app.loadDashboard()
          : app.loadOrganizationDashboard(),
    ]);
  }

  void _pickPeriod(ReportPeriod period) {
    final app = context.read<AppState>();
    final now = DateTime.now();
    app.setReportFilters(
      period: period,
      schoolYear: period.needsSchoolYear && app.reportSchoolYear == null
          ? SchoolYear.current(now)
          : null,
      semester: period.needsSemester && app.reportSemester == null
          ? _semesterOf(now)
          : null,
    );
    app.loadFinancialReport();
  }

  /// August to December is the first semester, January to May the
  /// second, June and July the summer.
  static Semester _semesterOf(DateTime now) => switch (now.month) {
    >= 8 => Semester.first,
    <= 5 => Semester.second,
    _ => Semester.summer,
  };

  void _showLedger(LedgerFilter filter) => setState(() {
    _filter = filter;
    _tab = _Tab.ledger;
  });

  void _openFilters() => BrutSheet.show<void>(
    context,
    builder: (_) => BrutSheet(
      title: 'Period and scope',
      subtitle: 'What the figures cover.',
      child: _Filters(onApply: _reload),
    ),
  );

  Future<void> _export(ExportFormat format) async {
    setState(() => _exporting = true);

    final messenger = ScaffoldMessenger.of(context);
    final outcome = await context.read<AppState>().exportFinancialReport(
      format,
    );

    if (!mounted) return;
    setState(() => _exporting = false);

    final file = outcome.file;
    if (file == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(outcome.error!),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    // The bytes arrived and were validated. Show them before anything
    // leaves the device: sharing used to be the only thing that happened
    // after an export, so the first look anyone got at a report was in
    // whatever app they had already sent it to.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExportPreviewScreen(
          file: file,
          format: format,
          subject: 'SMARTEVENT financial report',
        ),
      ),
    );
  }

  /// The downloads, in a window of their own.
  ///
  /// The snapshot first, so what is about to be exported is visible
  /// before choosing a format, then the three formats as squares.
  void _openDownloads(
    BuildContext context,
    ConsolidatedFinancialReport? report,
  ) {
    BrutSheet.show<void>(
      context,
      builder: (sheetContext) => BrutSheet(
        title: 'Download',
        subtitle: report == null
            ? 'Choose a period first for the full report.'
            : report.period.label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (report != null) ...[
              _TotalsCard(report: report),
              const SizedBox(height: 14),
              const BrutSectionTitle('This report'),
              const SizedBox(height: 10),
              ReportGrid(
                children: [
                  for (final (label, icon, format) in [
                    ('PDF', Icons.picture_as_pdf_outlined, ExportFormat.pdf),
                    ('CSV', Icons.table_chart_outlined, ExportFormat.csv),
                    ('Print-ready', Icons.print_outlined, ExportFormat.html),
                  ])
                    ReportActionTile(
                      label: label,
                      icon: icon,
                      busy: _exporting,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _export(format);
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppLayout.section),
            ],
            const BrutSectionTitle('Dashboard snapshot'),
            const SizedBox(height: 4),
            const Text(
              'Where things stand right now, whatever period is chosen.',
              style: AppText.caption,
            ),
            const SizedBox(height: 10),
            ReportGrid(
              children: [
                for (final (label, icon, format) in [
                  ('PDF', Icons.picture_as_pdf_outlined, ExportFormat.pdf),
                  ('CSV', Icons.table_chart_outlined, ExportFormat.csv),
                ])
                  ReportActionTile(
                    label: label,
                    icon: icon,
                    busy: _exporting,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _exportDashboard(format);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The dashboard snapshot, which takes no period filters.
  Future<void> _exportDashboard(ExportFormat format) async {
    setState(() => _exporting = true);

    final messenger = ScaffoldMessenger.of(context);
    final outcome = await context.read<AppState>().exportDashboard(format);

    if (!mounted) return;
    setState(() => _exporting = false);

    final file = outcome.file;
    if (file == null) {
      messenger.showSnackBar(SnackBar(content: Text(outcome.error!)));
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExportPreviewScreen(
          file: file,
          format: format,
          subject: 'SMARTEVENT dashboard',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.financialReportLoad;
    final report = app.financialReport;
    final dashboard = app.reportOrganizationId == null
        ? app.dashboard
        : app.organizationDashboard;

    return BrutScreen(
      // No canvas tint. A 12% wash of the module's colour was the old
      // answer to "sixteen screens look the same"; the band below says
      // it in full colour now, and this would be the only screen in
      // the app whose page is not the same cream as the rest.
      onRefresh: _reload,
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      // Downloading is one deliberate act, so it is one button in the
      // corner rather than a fold at the bottom of a long list.
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openDownloads(context, report),
        tooltip: 'Download',
        child: const Icon(Icons.download),
      ),
      bottomPadding: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.between),
          ModuleBand(
            module: Module.reports,
            subtitle: report == null
                ? 'Income, spending and budgets over a period.'
                : windowLabel(report),
          ),
          const SizedBox(height: AppLayout.section),
          BrutChipBar(
            children: [
              for (final period in const [
                ReportPeriod.schoolYear,
                ReportPeriod.semester,
                ReportPeriod.monthly,
                ReportPeriod.weekly,
              ])
                BrutChip(
                  label: period.label,
                  // The app's own selected colour, not orange. Orange
                  // is Money's, and a selected chip here sat under a
                  // gold Analytics band reading as a stray piece of
                  // the money area. Every other chip bar in the app —
                  // Inventory's, the ledger's below — marks the chosen
                  // one this way.
                  selected: app.reportPeriod == period,
                  onTap: () => _pickPeriod(period),
                ),
              BrutChip(
                label: 'More filters',
                selected: false,
                onTap: _openFilters,
              ),
            ],
          ),
          const SizedBox(height: AppLayout.section),
          // Not chips.
          //
          // These were a row of BrutChips directly under a chip bar of
          // BrutChips, so six identical controls sat stacked and only
          // the top three filtered anything — the bottom three change
          // which page you are reading. One shape, two jobs, nothing
          // saying which was which.
          //
          // A segmented bar instead: one block, divided, with the
          // chosen part filled. It reads as "where am I" rather than
          // as another thing to switch on and off.
          SegmentedSwitch<_Tab>(
            value: _tab,
            onChanged: (tab) => setState(() => _tab = tab),
            segments: const [
              (_Tab.overview, 'Overview'),
              (_Tab.events, 'Events'),
              (_Tab.ledger, 'Ledger'),
            ],
          ),
          const SizedBox(height: AppLayout.section),
          if (load.isLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Center(child: BrutSpinner(size: 22)),
            ),
          if (load.hasFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: BrutInlineMessage(text: load.error!, tone: BrutTone.coral),
            ),
          if (report == null)
            load.isLoading ? const SizedBox.shrink() : const _NotYetGenerated()
          else
            switch (_tab) {
              _Tab.overview => _Overview(
                report: report,
                dashboard: dashboard,
                onFilter: _showLedger,
              ),
              _Tab.events => _Events(report: report, onFilter: _showLedger),
              _Tab.ledger => _Ledger(
                report: report,
                filter: _filter,
                onFilter: (f) => setState(() => _filter = f),
              ),
            },
        ],
      ),
    );
  }
}

/// The window and filters the backend actually applied, as returned.
String windowLabel(ConsolidatedFinancialReport report) {
  String date(DateTime? value) => value == null
      ? '—'
      : '${value.year}-${value.month.toString().padLeft(2, '0')}'
            '-${value.day.toString().padLeft(2, '0')}';
  return [
    report.period.label,
    if (report.startDate != null || report.endDate != null)
      '${date(report.startDate)} to ${date(report.endDate)}',
    ?report.schoolYear,
    if (report.semester != null) report.semester!.label,
    if (report.eventScope != null) report.eventScope!.label,
  ].join(' · ');
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.report,
    required this.dashboard,
    required this.onFilter,
  });

  final ConsolidatedFinancialReport report;
  final DashboardSummary? dashboard;
  final ValueChanged<LedgerFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final charts = ReportChart.all(
      report,
      dashboard: dashboard,
      summary: context.watch<AppState>().proposalSummary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Kpis(report: report),
        const SizedBox(height: AppLayout.section),
        _Insights(items: reportInsights(report)),
        const SizedBox(height: AppLayout.section),
        const BrutSectionTitle('Charts'),
        const SizedBox(height: 10),
        // The trend reads left to right, so it gets the full width.
        ReportChartTile(
          chart: charts.first,
          onFilter: onFilter,
          height: 160,
          width: 360,
        ),
        const SizedBox(height: 10),
        ReportGrid(
          children: [
            for (final chart in charts.skip(1))
              ReportChartTile(chart: chart, onFilter: onFilter),
          ],
        ),
        if (dashboard != null) ...[
          const SizedBox(height: AppLayout.section),
          NeedsALook(data: dashboard!),
        ],
      ],
    );
  }
}

/// Four headline figures, each against the period before.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.report});

  final ConsolidatedFinancialReport report;

  static String? _change(double now, double? before) {
    if (before == null) return null;
    if (before == 0) {
      return now == 0 ? 'Same as the period before' : 'None the period before';
    }
    final change = (now - before) / before.abs();
    // Words, not arrows: the app's fonts carry no arrow glyphs.
    return '${change >= 0 ? 'Up' : 'Down'} ${(change.abs() * 100).round()}% '
        'on the period before';
  }

  @override
  Widget build(BuildContext context) {
    final before = report.previous;
    final used = report.budgetUsed;
    final net = report.netBalance;
    return ReportGrid(
      children: [
        BrutMetricTile(
          label: 'Income',
          value: peso(report.totalIncome, decimals: 0),
          tone: BrutTone.mint,
          footnote: _change(report.totalIncome, before?.totalIncome),
        ),
        BrutMetricTile(
          label: 'Spending',
          value: peso(report.totalExpenses, decimals: 0),
          tone: BrutTone.orange,
          footnote: _change(report.totalExpenses, before?.totalExpenses),
        ),
        BrutMetricTile(
          label: 'Net balance',
          value: peso(net, decimals: 0),
          tone: net < 0 ? BrutTone.coral : BrutTone.neutral,
          footnote: _change(net, before?.netBalance),
        ),
        BrutMetricTile(
          label: 'Budget used',
          value: used == null ? '—' : '${(used * 100).round()}%',
          tone: used == null
              ? BrutTone.neutral
              : used > 1
              ? BrutTone.coral
              : BrutTone.brand,
          footnote: used == null
              ? 'No approved event budgets yet'
              : '${peso(report.totalSpentToDate, decimals: 0)} of '
                    '${peso(report.totalAllocatedBudget, decimals: 0)}',
        ),
      ],
    );
  }
}

class _Insights extends StatelessWidget {
  const _Insights({required this.items});

  final List<ReportInsight> items;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrutSectionTitle('Worth knowing'),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text(
              'Nothing unusual in this period.',
              style: AppText.caption,
            )
          else
            for (final item in items) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.warning
                        ? Icons.error_outline
                        : Icons.lightbulb_outline,
                    size: 18,
                    color: item.warning
                        ? BrutTone.coral.fill(context)
                        : context.palette.subtle,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.text, style: AppText.body)),
                ],
              ),
              if (item != items.last) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _Events extends StatelessWidget {
  const _Events({required this.report, required this.onFilter});

  final ConsolidatedFinancialReport report;
  final ValueChanged<LedgerFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final event in report.events) {
      final status = event.status;
      if (status != null) counts[status] = (counts[status] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusCounts(title: 'Events by status', counts: counts),
        const SizedBox(height: AppLayout.section),
        if (report.events.isEmpty)
          const BrutEmptyState(
            title: 'No events in this period',
            hint: 'Widen the period, or clear the scope filter.',
            icon: Icons.event_busy_outlined,
          )
        else ...[
          BrutSectionTitle(
            'Events',
            aside: MonoLabel('${report.events.length} in period'),
          ),
          const SizedBox(height: 4),
          const Text(
            'Budget and spent to date cover the whole event. In and out are '
            'this period only.',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          for (final event in report.events) ...[
            _EventRow(event: event, onFilter: onFilter),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onFilter});

  final FinancialEventSummary event;
  final ValueChanged<LedgerFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final item = app.events
        .where((e) => e.remoteId == event.eventId)
        .firstOrNull;
    final status = event.status;
    final budget = event.allocatedBudget;

    return BrutCard(
      onTap: item == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EventReportScreen(event: item),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  event.title,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (status != null) ...[
                const SizedBox(width: 8),
                BrutBadge(
                  label: eventStatusLabel(status),
                  tone: eventStatusTone(status),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (budget > 0) ...[
            Row(
              children: [
                Expanded(
                  child: MonoLabel(
                    'Spent ${peso(event.spentToDate, decimals: 0)} of '
                    '${peso(budget, decimals: 0)}',
                  ),
                ),
                const SizedBox(width: 8),
                // A budget not yet approved is a request, so it has no
                // variance to speak of.
                BrutBadge(
                  label: event.isCommitted ? varianceLabel(event) : 'Proposed',
                  tone: event.isOverBudget
                      ? BrutTone.coral
                      : event.isCommitted
                      ? BrutTone.mint
                      : BrutTone.neutral,
                  mono: true,
                ),
              ],
            ),
            const SizedBox(height: 6),
            BrutProgressBar(
              value: event.spentToDate / budget,
              tone: event.isOverBudget ? BrutTone.coral : BrutTone.brand,
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              _Figure('In', peso(event.totalIncome, decimals: 0)),
              _Figure('Out', peso(event.totalExpenses, decimals: 0)),
              _Figure('Net', peso(event.netBalance, decimals: 0)),
            ],
          ),
          if (event.withheldIncomeCount > 0) ...[
            const SizedBox(height: 8),
            BrutBadge(
              label: '${peso(event.withheldIncomeTotal)} withheld',
              tone: BrutTone.sun,
              mono: true,
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: BrutChip(
              label: 'Show in ledger',
              selected: false,
              onTap: () => onFilter(
                LedgerFilter(eventId: event.eventId, title: event.title),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MonoLabel(label),
        const SizedBox(height: 2),
        Text(value, style: AppText.number, maxLines: 1),
      ],
    ),
  );
}

/// Every entry the totals are built from, newest first.
class _Ledger extends StatefulWidget {
  const _Ledger({
    required this.report,
    required this.filter,
    required this.onFilter,
  });

  final ConsolidatedFinancialReport report;
  final LedgerFilter filter;
  final ValueChanged<LedgerFilter> onFilter;

  @override
  State<_Ledger> createState() => _LedgerState();
}

class _LedgerState extends State<_Ledger> {
  /// Newest first, which is the order a ledger is read in. It had no
  /// order at all before — whatever the backend sent, which is its own
  /// choice and not one anybody here made.
  bool _newestFirst = true;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final filter = widget.filter;
    final onFilter = widget.onFilter;
    final rows = report.ledger.where(filter.matches).toList()
      ..sort(
        (a, b) => _newestFirst
            ? b.occurredOn.compareTo(a.occurredOn)
            : a.occurredOn.compareTo(b.occurredOn),
      );
    var income = 0.0;
    var spending = 0.0;
    for (final row in rows.where((r) => r.counted)) {
      row.isIncome ? income += row.amount : spending += row.amount;
    }
    final narrowed = filter.title != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutChipBar(
          children: [
            for (final (label, kind) in const [
              ('All', null),
              ('Income', true),
              ('Spending', false),
            ])
              BrutChip(
                label: label,
                selected: !narrowed && filter.income == kind,
                onTap: () => onFilter(LedgerFilter(income: kind)),
              ),
            if (narrowed)
              BrutChip(
                label: '${filter.title}  ✕',
                selected: true,
                tone: BrutTone.orange,
                onTap: () => onFilter(LedgerFilter.all),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: MonoLabel(
                '${rows.length} ${rows.length == 1 ? 'entry' : 'entries'} · '
                'in ${peso(income, decimals: 0)} · '
                'out ${peso(spending, decimals: 0)}',
              ),
            ),
            // The direction, said as a word and shown as an arrow. An
            // arrow alone leaves you working out which way it means.
            BrutChip(
              label: _newestFirst ? 'Newest ↓' : 'Oldest ↑',
              selected: false,
              onTap: () => setState(() => _newestFirst = !_newestFirst),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const BrutEmptyState(
            title: 'No entries',
            hint: 'Nothing recorded matches in this period.',
            icon: Icons.receipt_long_outlined,
          )
        else
          for (final row in rows) ...[
            _LedgerRow(row: row),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.row});

  final LedgerEntry row;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final where =
        row.eventTitle ?? (row.isIncome ? 'General fund' : 'No event');
    final kind = row.isIncome && row.sourceType != null
        ? '${row.sourceType!.label}: ${row.label}'
        : row.label;

    return BrutCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                MonoLabel(_months[row.occurredOn.month - 1]),
                Text('${row.occurredOn.day}', style: AppText.number),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.description,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  kind,
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                MonoLabel(where),
                if (!row.counted || row.flagged) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (!row.counted)
                        const BrutBadge(
                          label: 'Not counted',
                          tone: BrutTone.sun,
                        ),
                      if (row.flagged)
                        const BrutBadge(label: 'Flagged', tone: BrutTone.coral),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${row.isIncome ? '+' : '−'}${peso(row.amount)}',
            style: AppText.number,
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.onApply});

  final Future<void> Function() onApply;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final period = app.reportPeriod;
    final problem = app.reportFilterProblem;

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutDropdown<ReportPeriod>(
            label: 'Period',
            value: period,
            hint: 'Select a period',
            items: [
              for (final p in ReportPeriod.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) {
              if (v != null) app.setReportFilters(period: v);
            },
          ),
          const SizedBox(height: 6),
          // Calendar and academic periods answer different questions, so
          // which one is in use is stated rather than implied.
          Text(period.explanation, style: AppText.caption),
          if (period.usesReferenceDate) ...[
            const SizedBox(height: 14),
            BrutDateField(
              label: 'Reference date',
              value: app.reportReferenceDate,
              hint: 'Today',
              onTap: () async {
                final now = DateTime.now();
                final picked = await BrutDatePicker.show(
                  context,
                  initial: app.reportReferenceDate ?? now,
                  firstDate: DateTime(now.year - 5),
                  lastDate: DateTime(now.year + 1),
                  title: 'Reference date',
                  subtitle: 'The report is worked out as of this day.',
                );
                if (picked != null) {
                  app.setReportFilters(referenceDate: picked);
                }
              },
            ),
          ],
          if (period.needsSchoolYear) ...[
            const SizedBox(height: 14),
            BrutDropdown<String>(
              label: 'School year',
              value: app.reportSchoolYear,
              hint: 'Select a school year',
              items: [
                for (final year in SchoolYear.mergeOptions(
                  app.knownSchoolYears,
                  DateTime.now(),
                ))
                  DropdownMenuItem(value: year, child: Text(year)),
              ],
              onChanged: (v) {
                if (v != null) app.setReportFilters(schoolYear: v);
              },
            ),
          ],
          if (period.needsSemester) ...[
            const SizedBox(height: 14),
            BrutDropdown<Semester>(
              label: 'Semester',
              value: app.reportSemester,
              hint: 'Select a semester',
              items: [
                for (final s in Semester.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) {
                if (v != null) app.setReportFilters(semester: v);
              },
            ),
          ],
          const SizedBox(height: 14),
          const ReportOrganizationPicker(),
          const SizedBox(height: 14),
          const MonoLabel('Event scope'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BrutChip(
                label: 'All',
                selected: app.reportEventScope == null,
                onTap: () => app.setReportFilters(clearScope: true),
              ),
              for (final scope in EventScope.values)
                BrutChip(
                  label: scope.label,
                  selected: app.reportEventScope == scope,
                  onTap: () => app.setReportFilters(eventScope: scope),
                ),
            ],
          ),
          if (problem != null) ...[
            const SizedBox(height: 14),
            BrutInlineMessage(text: problem, tone: BrutTone.sun),
          ],
          const SizedBox(height: 18),
          BrutButton(
            label: 'Show these figures',
            icon: Icons.insights_outlined,
            onPressed: problem != null
                ? null
                : () {
                    Navigator.of(context).pop();
                    onApply();
                  },
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.report});

  final ConsolidatedFinancialReport report;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _figure('Income', report.totalIncome),
          const SizedBox(height: 12),
          _figure('Approved spending', report.totalExpenses),
          const Divider(height: 24),
          _figure(
            'Net balance',
            report.netBalance,
            tone: report.netBalance < 0 ? BrutTone.coral : BrutTone.mint,
          ),
        ],
      ),
    );
  }

  Widget _figure(String label, double value, {BrutTone? tone}) {
    return Row(
      children: [
        Expanded(child: MonoLabel(label)),
        if (tone != null)
          BrutBadge(label: peso(value), tone: tone, mono: true)
        else
          Text(peso(value), style: AppText.number),
      ],
    );
  }
}

class _NotYetGenerated extends StatelessWidget {
  const _NotYetGenerated();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: BrutEmptyState(
        icon: Icons.insights_outlined,
        title: 'No figures yet',
        hint: 'Pick a period above, or pull down to try again.',
      ),
    );
  }
}
