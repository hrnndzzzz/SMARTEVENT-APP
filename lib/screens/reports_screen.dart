import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/report_charts.dart';
import '../widgets/report_tiles.dart';
import 'analytics_sheet.dart';
import 'export_preview_screen.dart';
import '../widgets/app_header.dart';
import '../widgets/brut_date_picker.dart';
import '../theme/peso.dart';
import '../widgets/module_band.dart';

/// Consolidated financial reports.
///
/// Three things this screen is deliberate about:
///
///  * The **report's own totals are displayed**, never a sum of the event
///    rows shown. Unassigned spending and withheld income mean those two
///    figures legitimately differ, and the report is the correct one.
///  * The **window the backend actually used** is shown, so the figures and
///    the stated range always agree.
///  * An **export uses the filters currently on screen**, so the file
///    cannot disagree with what was read.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _exporting = false;

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

    return BrutScreen(
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      scrollable: false,
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
          const SizedBox(height: AppLayout.contentPadding),
          const ModuleBand(
            icon: Icons.insights_outlined,
            title: 'Financial reports',
            tone: BrutTone.orange,
            subtitle: 'Income and approved spending over a period.',
          ),
          const SizedBox(height: AppLayout.contentPadding),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppLayout.contentPadding),
              children: [
                // Charts first, four of them, two to a row. Each tile
                // opens the same chart full screen, where there is room
                // to read it.
                const BrutSectionTitle('Charts'),
                const SizedBox(height: 10),
                ReportGrid(
                  children: [
                    for (final chart in ReportChart.all(
                      budgets: app.categoryBudgets,
                      spend: app.spendByCategory,
                      sources: report?.incomeBySource ?? const [],
                      events: report?.events ?? const [],
                    ))
                      ReportChartTile(chart: chart),
                  ],
                ),
                const SizedBox(height: AppLayout.section),

                // The two things that change what the charts are of,
                // squared the same way as everything else here.
                const BrutSectionTitle('Narrow it down'),
                const SizedBox(height: 10),
                ReportGrid(
                  children: [
                    ReportActionTile(
                      label: 'Period and scope',
                      icon: Icons.tune,
                      detail: report == null
                          ? 'Nothing chosen yet'
                          : report.period.label,
                      tone: report == null ? BrutTone.sun : BrutTone.neutral,
                      onTap: () => BrutSheet.show<void>(
                        context,
                        builder: (_) => const BrutSheet(
                          title: 'Period and scope',
                          subtitle: 'What the figures cover.',
                          child: _Filters(),
                        ),
                      ),
                    ),
                    ReportActionTile(
                      label: 'Organization analytics',
                      icon: Icons.insights_outlined,
                      detail: 'Across the whole organization',
                      onTap: () => BrutSheet.show<void>(
                        context,
                        builder: (_) => const AnalyticsSheet(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppLayout.section),

                if (load.isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: BrutSpinner(),
                    ),
                  )
                else if (load.hasFailed)
                  _ErrorCard(message: load.error!)
                else if (report == null)
                  const _NotYetGenerated()
                else ...[
                  _WindowCard(report: report),
                  const SizedBox(height: 14),
                  _TotalsCard(report: report),
                  const SizedBox(height: 14),
                  if (report.incomeBySource.isNotEmpty) ...[
                    _SourcesCard(report: report),
                    const SizedBox(height: 14),
                  ],
                  _EventsCard(report: report),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters();

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
            label: 'Generate report',
            icon: Icons.insert_chart_outlined,
            onPressed: problem != null ? null : app.loadFinancialReport,
          ),
        ],
      ),
    );
  }
}

/// The window and filters the backend actually applied, shown as returned.
class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.report});

  final ConsolidatedFinancialReport report;

  static String _date(DateTime? value) => value == null
      ? '—'
      : '${value.year}-${value.month.toString().padLeft(2, '0')}'
            '-${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final parts = [
      report.period.label,
      if (report.startDate != null || report.endDate != null)
        '${_date(report.startDate)} to ${_date(report.endDate)}',
      if (report.schoolYear != null) report.schoolYear!,
      if (report.semester != null) report.semester!.label,
      if (report.eventScope != null) report.eventScope!.label,
    ];

    return BrutCard(
      tone: BrutTone.brand,
      tinted: true,
      radius: AppRadius.rowAll,
      shadow: AppShadows.sm,
      padding: const EdgeInsets.all(12),
      child: MonoLabel(parts.join(' · ')),
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
          if (report.hasWithheldIncome) ...[
            const SizedBox(height: 14),
            BrutInlineMessage(
              tone: BrutTone.sun,
              icon: Icons.pause_circle_outline,
              text:
                  '${peso(report.withheldIncomeTotal)} of '
                  'income (${report.withheldIncomeCount} '
                  '${report.withheldIncomeCount == 1 ? 'entry' : 'entries'}) '
                  'is held out of these totals pending a receipt decision.',
            ),
          ],
          if (report.hasUnassignedSpending) ...[
            const SizedBox(height: 10),
            BrutInlineMessage(
              tone: BrutTone.sun,
              icon: Icons.link_off,
              text:
                  '${peso(report.unassignedExpenseTotal)} of '
                  'spending is not linked to any event, so it is in the '
                  'total above but in none of the events below.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _figure(String label, double value, {BrutTone? tone}) {
    return Row(
      children: [
        Expanded(child: MonoLabel(label)),
        if (tone != null)
          BrutBadge(label: '${peso(value)}', tone: tone, mono: true)
        else
          Text('${peso(value)}', style: AppText.number),
      ],
    );
  }
}

class _SourcesCard extends StatelessWidget {
  const _SourcesCard({required this.report});

  final ConsolidatedFinancialReport report;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrutSectionTitle('Where the income came from'),
          const SizedBox(height: 12),
          for (final source in report.incomeBySource) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.source.isEmpty ? '—' : source.source,
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      MonoLabel(
                        '${source.sourceType.label} · '
                        '${source.incomeCount} '
                        '${source.incomeCount == 1 ? 'entry' : 'entries'}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text('${peso(source.totalIncome)}', style: AppText.number),
              ],
            ),
            if (source != report.incomeBySource.last) const Divider(height: 20),
          ],
        ],
      ),
    );
  }
}

class _EventsCard extends StatelessWidget {
  const _EventsCard({required this.report});

  final ConsolidatedFinancialReport report;

  @override
  Widget build(BuildContext context) {
    if (report.events.isEmpty) {
      return const BrutCard(
        child: BrutEmptyState(
          title: 'No events in this period',
          hint: 'Widen the period, or clear the scope filter.',
          icon: Icons.event_busy_outlined,
        ),
      );
    }

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrutSectionTitle(
            'Events',
            aside: MonoLabel('${report.events.length} in period'),
          ),
          const SizedBox(height: 4),
          // Saying this plainly, because the two figures genuinely differ.
          const Text(
            'These rows do not necessarily add up to the totals above.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          for (final event in report.events) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      MonoLabel(
                        [
                          if (event.schoolYear != null) event.schoolYear!,
                          if (event.semester != null)
                            event.semester!.shortLabel,
                          if (event.eventScope != null) event.eventScope!.label,
                        ].join(' · '),
                      ),
                      if (event.withheldIncomeCount > 0) ...[
                        const SizedBox(height: 6),
                        BrutBadge(
                          label: '${peso(event.withheldIncomeTotal)} withheld',
                          tone: BrutTone.sun,
                          mono: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('+${peso(event.totalIncome)}', style: AppText.number),
                    const SizedBox(height: 2),
                    Text(
                      '−${peso(event.totalExpenses)}',
                      style: AppText.moneySmall,
                    ),
                  ],
                ),
              ],
            ),
            if (event != report.events.last) const Divider(height: 20),
          ],
        ],
      ),
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
        icon: Icons.insert_chart_outlined,
        title: 'No report yet',
        hint: 'Choose a period and generate one.',
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return BrutInlineMessage(text: message, tone: BrutTone.coral);
  }
}
