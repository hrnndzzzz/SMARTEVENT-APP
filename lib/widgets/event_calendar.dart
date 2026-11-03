import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'event_status.dart';
import 'month_grid.dart';

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
                    '${monthNames[_month.month - 1]} ${_month.year}',
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
        MonthGrid(
          month: _month,
          selected: _selected,
          onSelect: (day) => setState(() => _selected = day),
          dotsFor: (day) => [
            for (final e in _on(day)) eventStatusTone(e.status),
          ],
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
  final weekday = weekdayNames[day.weekday - 1];
  return '$weekday ${day.day} ${monthNames[day.month - 1]}';
}

/// The long status labels name the desk a proposal is on, which is right
/// on a detail screen and far too long for a row's meta line.
String _shortStatus(EventApprovalStatus s) => switch (s) {
  EventApprovalStatus.draft => 'Draft',
  EventApprovalStatus.pendingAdviser => 'With adviser',
  EventApprovalStatus.pendingAdmin => 'With admin',
  EventApprovalStatus.pendingInstitutional => 'With signatories',
  EventApprovalStatus.approved => 'Approved',
  EventApprovalStatus.rejected => 'Rejected',
  EventApprovalStatus.completed => 'Completed',
};

IconData _statusIcon(EventApprovalStatus s) => switch (s) {
  EventApprovalStatus.draft => Icons.edit_outlined,
  EventApprovalStatus.pendingAdviser ||
  EventApprovalStatus.pendingAdmin ||
  EventApprovalStatus.pendingInstitutional => Icons.hourglass_empty,
  EventApprovalStatus.approved => Icons.check,
  EventApprovalStatus.rejected => Icons.priority_high,
  EventApprovalStatus.completed => Icons.task_alt,
};
