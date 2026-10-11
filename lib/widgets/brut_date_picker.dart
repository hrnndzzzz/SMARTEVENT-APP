import 'package:flutter/material.dart';

import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'month_grid.dart';

/// The app's date picker: the same month grid the events calendar draws,
/// in a sheet.
///
/// Material's `showDatePicker` is a fine picker and the wrong one here —
/// it arrives with its own radii, its own ripples and its own idea of an
/// outline, so picking a date was the one moment the app stopped looking
/// like itself.
class BrutDatePicker extends StatefulWidget {
  const BrutDatePicker({
    super.key,
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    this.title = 'Pick a date',
    this.subtitle,
  });

  final DateTime? initial;

  /// Inclusive. Days before it are shown but refused, so the rule is
  /// visible rather than a month that simply will not respond.
  final DateTime firstDate;
  final DateTime lastDate;

  final String title;
  final String? subtitle;

  static Future<DateTime?> show(
    BuildContext context, {
    DateTime? initial,
    required DateTime firstDate,
    required DateTime lastDate,
    String title = 'Pick a date',
    String? subtitle,
  }) {
    return BrutSheet.show<DateTime>(
      context,
      builder: (_) => BrutDatePicker(
        initial: initial,
        firstDate: firstDate,
        lastDate: lastDate,
        title: title,
        subtitle: subtitle,
      ),
    );
  }

  @override
  State<BrutDatePicker> createState() => _BrutDatePickerState();
}

class _BrutDatePickerState extends State<BrutDatePicker> {
  late DateTime _month;
  late DateTime? _selected;

  @override
  void initState() {
    super.initState();
    // Open on the chosen date if there is one, otherwise on the earliest
    // month that is actually pickable.
    final anchor = widget.initial ?? widget.firstDate;
    _selected = widget.initial;
    _month = DateTime(anchor.year, anchor.month);
  }

  DateTime get _firstDay => DateTime(
    widget.firstDate.year,
    widget.firstDate.month,
    widget.firstDate.day,
  );
  DateTime get _lastDay => DateTime(
    widget.lastDate.year,
    widget.lastDate.month,
    widget.lastDate.day,
  );

  bool get _canStepBack => DateTime(
    _month.year,
    _month.month - 1,
    1,
  ).isAfter(DateTime(_firstDay.year, _firstDay.month - 1, 1));

  bool get _canStepOn => DateTime(
    _month.year,
    _month.month + 1,
    1,
  ).isBefore(DateTime(_lastDay.year, _lastDay.month + 1, 1));

  void _step(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
  }

  @override
  Widget build(BuildContext context) {
    return BrutSheet(
      title: widget.title,
      subtitle: widget.subtitle,
      footer: BrutButton(
        label: _selected == null
            ? 'Pick a day'
            : 'Use ${_selected!.day} ${monthNames[_selected!.month - 1]}',
        size: BrutSize.large,
        onPressed: _selected == null
            ? null
            : () => Navigator.of(context).pop(_selected),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${monthNames[_month.month - 1]} ${_month.year}',
                  style: AppText.cardTitle,
                ),
              ),
              BrutIconButton(
                icon: Icons.chevron_left,
                label: 'Previous month',
                size: 36,
                onPressed: _canStepBack ? () => _step(-1) : null,
              ),
              const SizedBox(width: AppLayout.tight),
              BrutIconButton(
                icon: Icons.chevron_right,
                label: 'Next month',
                size: 36,
                onPressed: _canStepOn ? () => _step(1) : null,
              ),
            ],
          ),
          const SizedBox(height: AppLayout.section),
          MonthGrid(
            month: _month,
            selected: _selected,
            onSelect: (day) => setState(() => _selected = day),
            isEnabled: (day) =>
                !day.isBefore(_firstDay) && !day.isAfter(_lastDay),
          ),
          const SizedBox(height: AppLayout.between),
          Center(
            child: MonoLabel(
              'From ${_firstDay.day} ${monthNames[_firstDay.month - 1]} '
              '${_firstDay.year}',
              color: context.palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}
