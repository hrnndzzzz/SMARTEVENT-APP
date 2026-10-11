import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'event_status.dart';

const List<String> _months = [
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

const List<String> _weekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// The events list, laid out as a month instead of a list.
///
/// Same events, same filter, read by date rather than by order. A dot
/// under a day carries that event's approval status, so a month tells you
/// where the term's load sits and which parts of it are still waiting on
/// somebody before a single row is read.
///
/// Unlike a diary, nothing is created *by* tapping a day: an event here
/// is a budgeted proposal that goes through two approvals, so the create
/// button opens the form rather than writing a day in place. Days in the
/// past are not special for the same reason — a proposal can be reviewed
/// long after it was filed, and a month that hid them would hide the
/// term's history.
class EventCalendar extends StatefulWidget {
  const EventCalendar({super.key, required this.events, this.onOpen});

  final List<EventItem> events;

  /// Opening one. Null makes the agenda read-only, which is what a role
  /// without event access gets.
  final void Function(EventItem event)? onOpen;

  @override
  State<EventCalendar> createState() => _EventCalendarState();
}

class _EventCalendarState extends State<EventCalendar> {
  /// The month on screen, as its first day.
  late DateTime _month;

  /// The day the agenda is showing. Starts on today, so the first thing
  /// the screen answers is "what about now".
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _month = DateTime(now.year, now.month);
  }

  /// Events that fall on one day, in date order.
  List<EventItem> _on(DateTime day) => widget.events
      .where((e) => e.on != null && DateUtils.isSameDay(e.on, day))
      .toList();

  void _step(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
  }

  void _toToday() {
    final now = DateTime.now();
    setState(() {
      _selected = DateTime(now.year, now.month, now.day);
      _month = DateTime(now.year, now.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;

    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    // Monday-first, to match the week as the school prints it. weekday is
    // 1..7 with Monday first already, so the offset is simply one less.
    final leading = DateTime(_month.year, _month.month).weekday - 1;

    final thisMonth = widget.events
        .where(
          (e) =>
              e.on != null &&
              e.on!.year == _month.year &&
              e.on!.month == _month.month,
        )
        .length;
    final undated = widget.events.where((e) => e.on == null).length;
    final agenda = _on(_selected);

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonoLabel(
                    thisMonth == 0
                        ? 'Nothing this month'
                        : '$thisMonth this month',
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_months[_month.month - 1]} ${_month.year}',
                    style: AppText.titleBig,
                  ),
                ],
              ),
            ),
            BrutIconButton(
              icon: Icons.chevron_left,
              label: 'Previous month',
              onPressed: () => _step(-1),
            ),
            const SizedBox(width: AppLayout.tight),
            BrutIconButton(
              icon: Icons.chevron_right,
              label: 'Next month',
              onPressed: () => _step(1),
            ),
          ],
        ),
        // Only when it would do something. A "Today" that is already
        // today is a button that does nothing.
        if (!isCurrentMonth) ...[
          const SizedBox(height: AppLayout.between),
          Align(
            alignment: Alignment.centerLeft,
            child: BrutChip(
              label: 'Back to today',
              selected: false,
              onTap: _toToday,
            ),
          ),
        ],
        const SizedBox(height: AppLayout.section),
        Row(
          children: [
            for (final name in _weekdays)
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
        const SizedBox(height: AppLayout.tight),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            // Slightly taller than wide, so the dots have their own line
            // rather than crowding the number.
            childAspectRatio: 0.88,
          ),
          itemCount: leading + days,
          itemBuilder: (context, i) {
            // The run-up to the 1st is blank rather than showing the
            // previous month's tail: a grey 29 three rows above a black
            // 29 is the one thing a month view must never do.
            if (i < leading) return const SizedBox.shrink();
            final day = DateTime(_month.year, _month.month, i - leading + 1);
            final events = _on(day);
            return _DayCell(
              day: day.day,
              isToday: DateUtils.isSameDay(day, today),
              isSelected: DateUtils.isSameDay(day, _selected),
              tones: [
                for (final e in events.take(3)) eventStatusTone(e.status),
              ],
              more: events.length > 3,
              onTap: () => setState(() => _selected = day),
            );
          },
        ),
        const SizedBox(height: AppLayout.section),
        BrutSectionTitle(
          _heading(_selected, today),
          aside: agenda.isEmpty ? null : MonoLabel('${agenda.length}'),
        ),
        const SizedBox(height: AppLayout.between),
        if (agenda.isEmpty)
          BrutCard(
            radius: AppRadius.rowAll,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 18,
                  color: context.palette.subtle,
                ),
                const SizedBox(width: AppLayout.between),
                Expanded(
                  child: Text(
                    'Nothing on this day.',
                    style: AppText.caption.copyWith(
                      color: context.palette.subtle,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (final event in agenda) ...[
            BrutListRow(
              title: event.title,
              meta: [
                _shortStatus(event.status),
                if (event.org.isNotEmpty) event.org,
                event.budget,
              ].join(' · '),
              marker: BrutIconTile(
                icon: _statusIcon(event.status),
                tone: eventStatusTone(event.status),
                size: 32,
              ),
              onTap: widget.onOpen == null ? null : () => widget.onOpen!(event),
            ),
            const SizedBox(height: AppLayout.tight),
          ],
        if (undated > 0) ...[
          const SizedBox(height: AppLayout.section),
          BrutInlineMessage(
            text:
                '$undated event${undated == 1 ? '' : 's'} '
                '${undated == 1 ? 'has' : 'have'} no date yet, so '
                '${undated == 1 ? 'it is' : 'they are'} not on the grid. '
                'The list shows every one.',
            icon: Icons.event_busy_outlined,
          ),
        ],
      ],
    );
  }
}

/// `TODAY`, or `WED 15 OCTOBER` for any other day.
String _heading(DateTime day, DateTime today) {
  if (DateUtils.isSameDay(day, today)) return 'Today';
  final weekday = _weekdays[day.weekday - 1];
  return '$weekday ${day.day} ${_months[day.month - 1]}';
}

/// The long status labels name the desk a proposal is on, which is right
/// on a detail screen and far too long for a row's meta line.
String _shortStatus(EventApprovalStatus s) => switch (s) {
  EventApprovalStatus.draft => 'Draft',
  EventApprovalStatus.pendingAdviser => 'With adviser',
  EventApprovalStatus.pendingAdmin => 'With admin',
  EventApprovalStatus.approved => 'Approved',
  EventApprovalStatus.rejected => 'Returned',
  EventApprovalStatus.completed => 'Completed',
};

IconData _statusIcon(EventApprovalStatus s) => switch (s) {
  EventApprovalStatus.draft => Icons.edit_outlined,
  EventApprovalStatus.pendingAdviser ||
  EventApprovalStatus.pendingAdmin => Icons.hourglass_empty,
  EventApprovalStatus.approved => Icons.check,
  EventApprovalStatus.rejected => Icons.priority_high,
  EventApprovalStatus.completed => Icons.task_alt,
};

/// One day.
///
/// Borderless unless it is today or the selected day — forty-two outlined
/// boxes would be forty-two buttons competing with the dots, which are
/// the part carrying information.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.tones,
    required this.more,
    required this.onTap,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final List<BrutTone> tones;
  final bool more;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = isSelected ? context.palette.ink : null;
    final on = isSelected ? context.palette.canvas : context.palette.ink;

    return Semantics(
      selected: isSelected,
      button: true,
      label: tones.isEmpty
          ? '$day'
          : '$day, ${tones.length}${more ? ' or more' : ''} event'
                '${tones.length == 1 && !more ? '' : 's'}',
      child: GestureDetector(
        onTap: onTap,
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
                  // A fixed-height strip, so a day with events and a day
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
