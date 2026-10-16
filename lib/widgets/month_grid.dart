import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

const List<String> monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Monday first, to match the week as the school prints it.
const List<String> weekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// One month of days, with the weekday strip above it.
///
/// Shared by the events calendar and the date picker so a month looks the
/// same wherever it appears — the only difference between the two is what
/// they put under a day and which days they allow.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.onSelect,
    this.dotsFor,
    this.isEnabled,
  });

  /// Any day in the month to draw; only its year and month are read.
  final DateTime month;

  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  /// Up to three tones to mark a day with. Null means no marks at all,
  /// which is what a picker wants.
  final List<BrutTone> Function(DateTime day)? dotsFor;

  /// Days this grid refuses. Null allows every day.
  final bool Function(DateTime day)? isEnabled;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    // weekday is 1..7 with Monday first already, so the run-up to the 1st
    // is simply one less than its weekday.
    final leading = DateTime(month.year, month.month).weekday - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final name in weekdayNames)
              Expanded(
                child: Center(
                  child: MonoLabel(
                    name[0],
                    color: context.palette.muted,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            // Slightly taller than wide, so the marks have their own line
            // rather than crowding the number.
            childAspectRatio: 0.88,
          ),
          itemCount: leading + days,
          itemBuilder: (context, i) {
            // The run-up is blank rather than showing the previous
            // month's tail: a grey 29 three rows above a black 29 is the
            // one thing a month view must never do.
            if (i < leading) return const SizedBox.shrink();
            final day = DateTime(month.year, month.month, i - leading + 1);
            return _DayCell(
              day: day.day,
              isToday: DateUtils.isSameDay(day, today),
              isSelected: DateUtils.isSameDay(day, selected),
              enabled: isEnabled?.call(day) ?? true,
              tones: dotsFor?.call(day).take(3).toList() ?? const [],
              more: (dotsFor?.call(day).length ?? 0) > 3,
              onTap: () => onSelect(day),
            );
          },
        ),
      ],
    );
  }
}

/// One day.
///
/// Borderless unless it is today or the selected day — forty-two outlined
/// boxes would be forty-two buttons competing with the marks, which are
/// the part carrying information.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.enabled,
    required this.tones,
    required this.more,
    required this.onTap,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final bool enabled;
  final List<BrutTone> tones;
  final bool more;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = isSelected ? context.palette.ink : null;
    final on = !enabled
        ? context.palette.muted
        : isSelected
        ? context.palette.canvas
        : context.palette.ink;

    return Semantics(
      selected: isSelected,
      enabled: enabled,
      button: true,
      label: tones.isEmpty
          ? '$day'
          : '$day, ${tones.length}${more ? ' or more' : ''} event'
                '${tones.length == 1 && !more ? '' : 's'}',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: AppRadius.controlAll,
            // Today keeps its outline whether or not it is selected, so
            // the month never loses its anchor.
            border: isToday && !isSelected ? context.borderAll : null,
          ),
          // Scaled rather than clipped: the grid has seven columns at any
          // text size, and a cell that overflowed would stripe the month.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$day',
                    style: AppText.number.copyWith(
                      fontSize: 14,
                      color: on,
                      fontWeight: isToday || isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // A fixed-height strip, so a day with marks and a day
                  // without still line up across the row.
                  SizedBox(
                    height: 7,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final tone in tones) ...[
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tone == BrutTone.neutral
                                  // A draft's "colour" is white, which is
                                  // invisible as a dot.
                                  ? context.palette.muted
                                  : tone.fill(context),
                            ),
                          ),
                          const SizedBox(width: 2),
                        ],
                        if (more)
                          Text(
                            '+',
                            style: AppText.number.copyWith(
                              fontSize: 11,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              color: on,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
