import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/financial_overview.dart';
import 'analytics_sheet.dart';
import 'export_preview_screen.dart';
import '../widgets/app_header.dart';
import '../widgets/brut_date_picker.dart';
import '../theme/peso.dart';

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
      topBar: AppHeader(
        onBack: () => Navigator.of(context).maybePop(),
      ),
      scrollable: false,
      bottomPadding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.contentPadding),
          const Text('Financial reports', style: AppText.screenTitle),
          const SizedBox(height: 4),
          const Text(
            'Income and approved spending over a period.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppLayout.contentPadding),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppLayout.contentPadding),
              children: [
                // The report is what this screen is for, so it opens on
                // it. The charts and the period controls are folded: both
                // are things you go to deliberately, and all of it at
                // once was a screen you had to scroll before you could
                // read anything.
                BrutFoldable(
                  title: 'Charts',
                  initiallyOpen: false,
                  children: [
                    BrutButton(
                      label: 'Organization analytics',
                      icon: Icons.bar_chart_outlined,
                      tone: BrutTone.neutral,
                      onPressed: () => BrutSheet.show<void>(
                        context,
                        builder: (_) => const AnalyticsSheet(),
                      ),
                    ),
                    const SizedBox(height: AppLayout.between),
                    AllocationVsActualCard(
                      budgets: app.categoryBudgets,
                      spend: app.spendByCategory,
                    ),
                    const SizedBox(height: AppLayout.between),
                    ExpenseDistributionCard(
                      spendByCategory: app.spendByCategory,
                    ),
                  ],
                ),
                const SizedBox(height: AppLayout.section),
                BrutFoldable(
                  title: 'Period and scope',
                  // Open while there is nothing to show, because then
                  // choosing a period is the next thing to do.
                  initiallyOpen: report == null,
                  children: const [_Filters()],
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: AppLayout.section),
                // Both downloads under one heading. They were a row, a
                // divider and a second row, which read as two unrelated
                // things rather than two of the same thing.
                BrutFoldable(
                  title: 'Download',
                  initiallyOpen: false,
                  children: [
                    if (report != null) ...[
                      _ExportRow(busy: _exporting, onExport: _export),
                      const SizedBox(height: 14),
                    ],
                    _DashboardExportRow(
                      busy: _exporting,
                      onExport: _exportDashboard,
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

class _ExportRow extends StatelessWidget {
  const _ExportRow({required this.busy, required this.onExport});

  final bool busy;
  final ValueChanged<ExportFormat> onExport;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BrutSectionTitle('Export'),
        const SizedBox(height: 4),
        const Text(
          'Uses the filters above, so the file matches what is shown. The '
          'HTML export is print-ready.',
          style: AppText.caption,
        ),
        const SizedBox(height: 12),
        _FormatButtons(busy: busy, onExport: onExport),
      ],
    );
  }
}

/// One button per export format, all the same width.
class _FormatButtons extends StatelessWidget {
  const _FormatButtons({required this.busy, required this.onExport});

  final bool busy;
  final ValueChanged<ExportFormat> onExport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final format in ExportFormat.values) ...[
          Expanded(
            child: BrutButton(
              label: format.label,
              tone: BrutTone.neutral,
              size: BrutSize.small,
              busy: busy,
              busyLabel: '…',
              onPressed: () => onExport(format),
            ),
          ),
          if (format != ExportFormat.values.last) const SizedBox(width: 8),
        ],
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

/// Exporting the dashboard snapshot.
///
/// Kept apart from the report export above because it answers a different
/// question and takes none of the period filters — presenting them together
/// would imply the dashboard respects them.
class _DashboardExportRow extends StatelessWidget {
  const _DashboardExportRow({required this.busy, required this.onExport});

  final bool busy;
  final ValueChanged<ExportFormat> onExport;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BrutSectionTitle('Dashboard snapshot'),
        const SizedBox(height: 4),
        const Text(
          'Current totals and counts. Not affected by the filters above.',
          style: AppText.caption,
        ),
        const SizedBox(height: 12),
        _FormatButtons(busy: busy, onExport: onExport),
      ],
    );
  }
}
