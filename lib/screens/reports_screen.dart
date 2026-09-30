import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/export_saver.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/scope_picker.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

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
    final outcome = await context.read<AppState>().exportFinancialReport(format);

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

    // The bytes arrived and were validated; hand them to the share sheet so
    // they can be saved, mailed or opened in a viewer.
    final shareProblem = await ExportSaver.share(
      file,
      subject: 'SMARTEVENT financial report',
    );

    if (shareProblem != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$shareProblem The report itself downloaded fine '
              '(${file.filename}, ${_size(file.sizeBytes)}).'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
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

    final shareProblem = await ExportSaver.share(
      file,
      subject: 'SMARTEVENT dashboard',
    );
    if (shareProblem != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$shareProblem The file downloaded fine '
              '(${file.filename}, ${_size(file.sizeBytes)}).'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  static String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(1)} KB'
          : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.financialReportLoad;
    final report = app.financialReport;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppHeader(
                    onAvatarTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountScreen()),
                    ),
                    onBellTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const NotificationsScreen()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Financial Reports',
                    style: TextStyle(
                      fontFamily: AppText.headerFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 18,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Income and approved spending over a period.',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  const _Filters(),
                  const SizedBox(height: 14),
                  if (load.isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
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
                    const SizedBox(height: 18),
                    _ExportRow(
                      busy: _exporting,
                      onExport: _export,
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  // Separate from the report above: this exports the
                  // dashboard snapshot, which has no period filters.
                  _DashboardExportRow(
                    busy: _exporting,
                    onExport: _exportDashboard,
                  ),
                ],
              ),
            ),
          ],
        ),
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Period', style: AppText.caption),
          const SizedBox(height: 6),
          LabeledDropdown<ReportPeriod>(
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
          const SizedBox(height: 4),
          // Calendar and academic periods answer different questions, so
          // which one is in use is stated rather than implied.
          Text(
            period.explanation,
            style: const TextStyle(
              fontFamily: AppText.bodyFamily,
              fontSize: 10,
              color: AppColors.inkFaint,
            ),
          ),

          if (period.usesReferenceDate) ...[
            const SizedBox(height: 14),
            const Text('Reference date', style: AppText.caption),
            const SizedBox(height: 6),
            _DateField(
              value: app.reportReferenceDate,
              onPick: (date) => app.setReportFilters(referenceDate: date),
            ),
          ],

          if (period.needsSchoolYear) ...[
            const SizedBox(height: 14),
            const Text('School year', style: AppText.caption),
            const SizedBox(height: 6),
            LabeledDropdown<String>(
              value: app.reportSchoolYear,
              hint: 'Select a school year',
              items: [
                for (final year
                    in SchoolYear.mergeOptions(app.knownSchoolYears, DateTime.now()))
                  DropdownMenuItem(value: year, child: Text(year)),
              ],
              onChanged: (v) {
                if (v != null) app.setReportFilters(schoolYear: v);
              },
            ),
          ],

          if (period.needsSemester) ...[
            const SizedBox(height: 14),
            const Text('Semester', style: AppText.caption),
            const SizedBox(height: 6),
            LabeledDropdown<Semester>(
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
          const Text('Event scope', style: AppText.caption),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              _ScopeChip(
                label: 'All',
                selected: app.reportEventScope == null,
                onTap: () => app.setReportFilters(clearScope: true),
              ),
              for (final scope in EventScope.values)
                _ScopeChip(
                  label: scope.label,
                  selected: app.reportEventScope == scope,
                  onTap: () => app.setReportFilters(eventScope: scope),
                ),
            ],
          ),

          if (problem != null) ...[
            const SizedBox(height: 12),
            Text(problem,
                style: AppText.caption.copyWith(color: AppColors.marigoldText)),
          ],

          const SizedBox(height: 16),
          FilledButton(
            onPressed: problem != null ? null : app.loadFinancialReport,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: const Text('Generate report'),
          ),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.indigo : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? AppColors.indigo : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppText.bodyFamily,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onPick});

  final DateTime? value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 1),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          value == null
              ? 'Today'
              : '${value!.year}-${value!.month.toString().padLeft(2, '0')}'
                  '-${value!.day.toString().padLeft(2, '0')}',
          style: TextStyle(
            fontFamily: AppText.bodyFamily,
            fontSize: 13,
            color: value == null ? AppColors.inkFaint : AppColors.ink,
          ),
        ),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.trackBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        parts.join(' · '),
        style: AppText.caption.copyWith(color: AppColors.ink),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.report});

  final ConsolidatedFinancialReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _figure('Income', report.totalIncome, AppColors.sageTealText),
          const SizedBox(height: 10),
          _figure('Approved spending', report.totalExpenses, AppColors.ink),
          const Divider(height: 22),
          _figure('Net balance', report.netBalance,
              report.netBalance < 0 ? AppColors.brick : AppColors.ink),

          if (report.hasWithheldIncome) ...[
            const SizedBox(height: 12),
            _note(
              '₱${report.withheldIncomeTotal.toStringAsFixed(2)} of income '
              '(${report.withheldIncomeCount} '
              '${report.withheldIncomeCount == 1 ? 'entry' : 'entries'}) is '
              'held out of these totals pending a receipt decision.',
            ),
          ],
          if (report.hasUnassignedSpending) ...[
            const SizedBox(height: 8),
            _note(
              '₱${report.unassignedExpenseTotal.toStringAsFixed(2)} of '
              'spending is not linked to any event, so it is in the total '
              'above but in none of the events below.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _figure(String label, double value, Color color) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppText.caption)),
        Text('₱${value.toStringAsFixed(2)}',
            style: AppText.moneySmall.copyWith(color: color)),
      ],
    );
  }

  Widget _note(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.marigoldTint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: AppText.caption.copyWith(color: AppColors.marigoldText)),
    );
  }
}

class _SourcesCard extends StatelessWidget {
  const _SourcesCard({required this.report});

  final ConsolidatedFinancialReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Where the income came from', style: AppText.cardTitle),
          const SizedBox(height: 10),
          for (final source in report.incomeBySource) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.source.isEmpty ? '—' : source.source,
                          style: AppText.body),
                      Text(
                        '${source.sourceType.label} · '
                        '${source.incomeCount} '
                        '${source.incomeCount == 1 ? 'entry' : 'entries'}',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                Text('₱${source.totalIncome.toStringAsFixed(2)}',
                    style: AppText.moneySmall),
              ],
            ),
            if (source != report.incomeBySource.last) const Divider(height: 18),
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
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'No events fall in this period.',
          style: AppText.caption,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Events (${report.events.length})', style: AppText.cardTitle),
          const SizedBox(height: 2),
          // Saying this plainly, because the two figures genuinely differ.
          const Text(
            'These rows do not necessarily add up to the totals above.',
            style: TextStyle(
              fontFamily: AppText.bodyFamily,
              fontSize: 10,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 10),
          for (final event in report.events) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title, style: AppText.body),
                      Text(
                        [
                          if (event.schoolYear != null) event.schoolYear!,
                          if (event.semester != null) event.semester!.shortLabel,
                          if (event.eventScope != null) event.eventScope!.label,
                        ].join(' · '),
                        style: AppText.caption,
                      ),
                      if (event.withheldIncomeCount > 0)
                        Text(
                          '₱${event.withheldIncomeTotal.toStringAsFixed(2)} '
                          'withheld',
                          style: AppText.caption
                              .copyWith(color: AppColors.marigoldText),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('+₱${event.totalIncome.toStringAsFixed(2)}',
                        style: AppText.moneySmall
                            .copyWith(color: AppColors.sageTealText)),
                    Text('−₱${event.totalExpenses.toStringAsFixed(2)}',
                        style: AppText.caption),
                  ],
                ),
              ],
            ),
            if (event != report.events.last) const Divider(height: 18),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Export', style: AppText.cardTitle),
        const SizedBox(height: 2),
        const Text(
          'Uses the filters above, so the file matches what is shown. The '
          'HTML export is print-ready.',
          style: AppText.caption,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final format in ExportFormat.values) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => onExport(format),
                  child: Text(format.label),
                ),
              ),
              if (format != ExportFormat.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
        if (busy) ...[
          const SizedBox(height: 10),
          const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
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
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.insert_chart_outlined, size: 44, color: AppColors.inkFaint),
          SizedBox(height: 14),
          Text('No report yet', style: AppText.cardTitle),
          SizedBox(height: 6),
          SizedBox(
            width: 280,
            child: Text(
              'Choose a period and generate one.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brick.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brick.withValues(alpha: 0.3)),
      ),
      child: Text(message,
          style: AppText.caption.copyWith(color: AppColors.brick)),
    );
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Dashboard snapshot', style: AppText.cardTitle),
        const SizedBox(height: 2),
        const Text(
          'Current totals and counts. Not affected by the filters above.',
          style: AppText.caption,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final format in ExportFormat.values) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => onExport(format),
                  child: Text(format.label),
                ),
              ),
              if (format != ExportFormat.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}
