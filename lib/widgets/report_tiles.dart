import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'report_charts.dart';

/// One chart, small, in the grid.
///
/// Tapping opens the same chart full screen. The tile and the page are
/// built from one definition, so they cannot drift apart.
class ReportChartTile extends StatelessWidget {
  const ReportChartTile({super.key, required this.chart});

  final ReportChart chart;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _ChartPage(chart: chart)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                // Two of these are existing cards that draw their own
                // heading, and a title here put the same words above
                // them twice.
                child: chart.selfTitled
                    ? const SizedBox.shrink()
                    : Text(
                        chart.title,
                        style: AppText.cardTitle.copyWith(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              Icon(Icons.open_in_full, size: 14, color: context.palette.ink),
            ],
          ),
          SizedBox(height: chart.selfTitled ? 4 : 10),
          // Scaled rather than cropped. Held to a height so four tiles
          // make an even grid, and whatever the chart draws is shrunk to
          // fit instead of having its bottom cut off.
          SizedBox(
            height: 150,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 260,
                child: chart.build(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A chart on its own, with room to read it.
class _ChartPage extends StatelessWidget {
  const _ChartPage({required this.chart});

  final ReportChart chart;

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
          BrutCard(child: chart.build(context)),
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
