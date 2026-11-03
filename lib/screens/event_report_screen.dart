import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models/reports.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/peso.dart';
import '../widgets/report_tiles.dart';
import 'export_preview_screen.dart';

/// One event's finances — the moderator's "a financial report per
/// event", and the liquidation an organization is asked for after the
/// activity has run.
///
/// The backend has answered `/reports/event/{id}` all along, and the
/// client has had `ReportsService.eventReport`, `exportEvent` and
/// `AppState.loadEventReport` for as long. No screen opened any of
/// them, so none of it had ever been seen.
class EventReportScreen extends StatefulWidget {
  const EventReportScreen({super.key, required this.event});

  final EventItem event;

  @override
  State<EventReportScreen> createState() => _EventReportScreenState();
}

class _EventReportScreenState extends State<EventReportScreen> {
  EventReport? _report;
  String? _error;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.event.remoteId;
    if (id == null) {
      setState(() {
        _loading = false;
        _error = 'This event has no real backend record yet.';
      });
      return;
    }

    final outcome = await context.read<AppState>().loadEventReport(id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _report = outcome.report;
      _error = outcome.error;
    });
  }

  Future<void> _export(ExportFormat format) async {
    final id = widget.event.remoteId;
    if (id == null) return;

    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final outcome = await context.read<AppState>().exportEventReport(
      id,
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

    // Shown before it is shared, the same way the other exports are: the
    // first look at a report should not be in whatever app it was sent
    // to.
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ExportPreviewScreen(
          file: file,
          format: format,
          subject: 'Financial report — ${widget.event.title}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BrutScreen(
      header: BrutHeader(
        eyebrow: 'Financial report',
        title: widget.event.title,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) ...[
            const SizedBox(height: 40),
            const Center(child: BrutSpinner()),
            const SizedBox(height: 40),
          ] else if (_report case final report?) ...[
            _Totals(report: report),
            const SizedBox(height: AppLayout.section),
            if (report.incomeBySource.isNotEmpty) ...[
              const BrutSectionTitle('Where the money came from'),
              const SizedBox(height: 10),
              BrutCard(
                child: Column(
                  children: [
                    for (final source in report.incomeBySource) ...[
                      BrutDetailRow(
                        source.source,
                        peso(source.totalIncome),
                        mono: true,
                      ),
                      if (source != report.incomeBySource.last)
                        const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppLayout.section),
            ],
            if (report.withheldIncomeCount > 0) ...[
              BrutInlineMessage(
                tone: BrutTone.sun,
                icon: Icons.pause_circle_outline,
                // Withheld income is not income until someone decides,
                // so it is named rather than folded into the total.
                text:
                    '${report.withheldIncomeCount} income '
                    '${report.withheldIncomeCount == 1 ? 'entry is' : 'entries are'} '
                    'withheld pending a receipt decision, worth '
                    '${peso(report.withheldIncomeTotal)}. '
                    'It is not counted above.',
              ),
              const SizedBox(height: AppLayout.section),
            ],
            const BrutSectionTitle('Take it with you'),
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
                    onTap: () => _export(format),
                  ),
              ],
            ),
          ] else
            BrutInlineMessage(
              tone: BrutTone.coral,
              icon: Icons.error_outline,
              text: _error ?? 'This report could not be loaded.',
            ),
        ],
      ),
    );
  }
}

/// What was allowed, what came in, what went out, and what is left.
class _Totals extends StatelessWidget {
  const _Totals({required this.report});

  final EventReport report;

  @override
  Widget build(BuildContext context) {
    // Negative means the event spent more than it took, which is the
    // one figure here worth colouring.
    final short = report.netBalance < 0;

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrutSectionTitle('The figures'),
          const SizedBox(height: 12),
          BrutDetailRow('Allocated', peso(report.allocatedBudget), mono: true),
          const SizedBox(height: 8),
          BrutDetailRow('Estimated cost', peso(report.estimatedCost),
              mono: true),
          const SizedBox(height: 8),
          BrutDetailRow('Income', peso(report.totalIncome), mono: true),
          const SizedBox(height: 8),
          // Approved spending only; pending and rejected are not
          // spending, and the model says so.
          BrutDetailRow('Approved spending', peso(report.totalSpent),
              mono: true),
          const SizedBox(height: 8),
          BrutDetailRow('Remaining budget', peso(report.remainingBudget),
              mono: true),
          const SizedBox(height: 12),
          BrutSurface(
            fill: (short ? BrutTone.coral : BrutTone.mint).tint(context),
            radius: AppRadius.controlAll,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    short ? 'Short by' : 'Net balance',
                    style: AppText.cardTitle.copyWith(fontSize: 13),
                  ),
                ),
                Text(
                  peso(report.netBalance.abs()),
                  style: AppText.moneyLarge.copyWith(fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
