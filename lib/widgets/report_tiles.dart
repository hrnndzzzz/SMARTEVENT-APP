import 'package:flutter/material.dart';

import '../state/report_insights.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'report_charts.dart';

/// One chart, small, in the grid.
///
/// Tapping opens the same chart full screen. The tile and the page are
/// built from one definition, so they cannot drift apart.
class ReportChartTile extends StatelessWidget {
  const ReportChartTile({
    super.key,
    required this.chart,
    this.onFilter,
    this.height = 150,
    this.width = 260,
  });

  final ReportChart chart;

  /// Called with a row's ledger filter when it is tapped on the full page.
  final ValueChanged<LedgerFilter>? onFilter;

  /// The space the chart is scaled into. A full-width tile is wider.
  /// A null height fills whatever height the tile is given.
  final double? height;
  final double width;

  @override
  Widget build(BuildContext context) {
    // Scaled rather than cropped, so whatever the chart draws is shrunk
    // to fit instead of having its bottom cut off.
    //
    // Laid out at the width it is actually being given, not at a fixed
    // [width] that is then scaled to fit. `contain` keeps the aspect
    // ratio, so a chart built at 360 and dropped into a box wider than
    // it is tall scaled down to the *height* and handed the leftover
    // width back as empty margin — a thumbnail adrift in a full-width
    // card. Built at the real width it scales by 1 whenever it fits,
    // which is almost always; [width] is only the fallback for an
    // unbounded parent, where there is no real width to ask for.
    final scaled = LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: constraints.hasBoundedWidth ? constraints.maxWidth : width,
          child: chart.build(context, false),
        ),
      ),
    );
    return BrutCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _ChartPage(chart: chart, onFilter: onFilter),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: height == null ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  chart.title,
                  style: AppText.cardTitle.copyWith(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.open_in_full, size: 14, color: context.palette.ink),
            ],
          ),
          const SizedBox(height: 10),
          // Held to a height so the tiles make an even grid.
          if (height case final h?)
            SizedBox(height: h, child: scaled)
          else
            Expanded(child: scaled),
        ],
      ),
    );
  }
}

/// A chart on its own, with room to read it and its exact figures below.
class _ChartPage extends StatelessWidget {
  const _ChartPage({required this.chart, this.onFilter});

  final ReportChart chart;
  final ValueChanged<LedgerFilter>? onFilter;

  @override
  Widget build(BuildContext context) {
    return BrutScreen(
      header: BrutHeader(
        title: chart.title,
        eyebrow: 'Chart',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(chart.explanation, style: AppText.caption),
          const SizedBox(height: 16),
          BrutCard(child: chart.build(context, true)),
          for (final (heading, text) in chart.notes) ...[
            const SizedBox(height: 20),
            BrutSectionTitle(heading),
            // Under the heading, above the writing it describes.
            //
            // It used to sit after both notes, so you read two
            // paragraphs about why proposals get rejected and only then
            // found out a machine had written them. A disclosure that
            // arrives after the claim it qualifies is not a disclosure,
            // and this is a reviewer's remarks being paraphrased by a
            // model — the one place in the app where the difference
            // between "the office said" and "a summary says" matters.
            if (chart.notesCaption case final caption?) ...[
              const SizedBox(height: 4),
              Text(
                caption,
                style: AppText.caption.copyWith(color: context.palette.subtle),
              ),
            ],
            const SizedBox(height: 8),
            Text(text, style: AppText.body),
          ],
          if (chart.rows.isNotEmpty) ...[
            const SizedBox(height: 20),
            const BrutSectionTitle('The figures'),
            const SizedBox(height: 10),
            for (final row in chart.rows) ...[
              BrutListRow(
                title: row.label,
                meta: row.detail,
                marker: row.colour == null
                    ? null
                    : LegendDot(color: row.colour!, label: ''),
                trailing: Text(row.value, style: AppText.number),
                onTap: row.filter == null || onFilter == null
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        onFilter!(row.filter!);
                      },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

/// A square action: period and scope, organization analytics, and the
/// three download formats all read the same way.
class ReportActionTile extends StatelessWidget {
  const ReportActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.detail,
    this.tone = BrutTone.neutral,
    this.busy = false,
    this.dense = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? detail;
  final BrutTone tone;
  final bool busy;

  /// Tighter, for a set of choices in a dialog rather than a page of
  /// actions. The reports screen's tiles carry a line of detail and
  /// have a page to sit on; three of these in a dialog do not.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: tone,
      onTap: busy ? null : onTap,
      padding: dense
          ? const EdgeInsets.symmetric(vertical: 8, horizontal: 8)
          : const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: dense ? 16 : 22,
              height: dense ? 16 : 22,
              child: BrutSpinner(size: dense ? 16 : 22),
            )
          else
            Icon(icon, size: dense ? 16 : 22, color: context.palette.ink),
          SizedBox(height: dense ? 5 : 10),
          Text(
            label,
            style: AppText.cardTitle.copyWith(fontSize: dense ? 12 : 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (detail case final line?) ...[
            const SizedBox(height: 4),
            Text(
              line,
              style: AppText.caption.copyWith(fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Two columns, any number of rows, even gaps.
class ReportGrid extends StatelessWidget {
  const ReportGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < children.length) rows.add(const SizedBox(height: 10));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
