import 'package:flutter/material.dart';
import 'sap/sap_proposal_flow.dart';
import '../state/sap_form.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import '../widgets/event_progress_bar.dart';
import '../widgets/floating_peek.dart';
import '../widgets/app_header.dart';
import '../widgets/event_calendar.dart';
import '../widgets/event_status.dart';
import '../widgets/last_change_note.dart';
import 'event_detail_screen.dart';

/// Every proposal, as a list or as a month.
///
/// The two views read the same filtered list — the school-year filter is
/// the server's, so switching views never changes which events are in
/// play, only how they are arranged.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  /// The list is the default: it is the whole filtered set in one
  /// scroll, and it is what every role already knows.
  bool _calendar = false;
  _StatusFilter _status = _StatusFilter.all;

  /// Soonest first by default: the list is read to find out what is
  /// coming, not to browse the archive.
  _EventSort _sort = _EventSort.dateAsc;

  void _open(EventItem event) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)));
  }

  @override
  Widget build(BuildContext context) {
    return BrutScreen(
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      scrollable: false,
      bottomPadding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Events', style: AppText.display)),
              _SortButton(
                sort: _sort,
                onChanged: (v) => setState(() => _sort = v),
              ),
              const SizedBox(width: AppLayout.tight),
              _ViewToggle(
                calendar: _calendar,
                onChanged: (v) => setState(() => _calendar = v),
              ),
              const SizedBox(width: AppLayout.tight),
              // SDS has no event access; the server decides who may
              // propose.
              if (context.watch<AppState>().mayProposeEvents)
                BrutButton(
                  label: 'New',
                  icon: Icons.add,
                  size: BrutSize.small,
                  expand: false,
                  onPressed: () {
                    final app = context.read<AppState>();
                    SapProposalFlow.start(
                      context,
                      SapForm(service: app.isDemoMode ? null : app.sapService),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          const LastChangeNote(area: 'proposals'),
          const SizedBox(height: 12),
          _EventFilterBar(
            status: _status,
            onStatus: (value) => setState(() => _status = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Consumer<AppState>(
              builder: (context, app, _) {
                if (app.eventsLoad.isLoading && app.events.isEmpty) {
                  return Center(child: BrutSpinner());
                }
                if (app.eventsLoad.hasFailed && app.events.isEmpty) {
                  return Center(
                    child: BrutEmptyState(
                      title: 'Could not load events',
                      hint: app.eventsLoad.error,
                      icon: Icons.cloud_off_outlined,
                      action: BrutButton(
                        label: 'Try again',
                        icon: Icons.refresh,
                        size: BrutSize.small,
                        expand: false,
                        tone: BrutTone.neutral,
                        onPressed: app.loadEvents,
                      ),
                    ),
                  );
                }
                if (app.events.isEmpty) {
                  final filtered =
                      app.schoolYearFilter != null ||
                      app.showOnlyMissingSchoolYear;
                  return Center(
                    child: BrutEmptyState(
                      icon: Icons.event_outlined,
                      // An active filter is a far likelier reason for
                      // an empty list than there being none.
                      title: filtered
                          ? 'No events match this filter'
                          : 'No events yet',
                      hint: filtered
                          ? 'Clear the filter to see every event.'
                          : app.mayProposeEvents
                          ? 'Tap New to submit one.'
                          : null,
                    ),
                  );
                }
                // One narrowing, both views: switching to the month
                // should not quietly widen what is on screen.
                final events = [
                  for (final event in app.events)
                    if (_status.matches(event.status)) event,
                ]..sort(_sort.compare);
                if (_calendar) {
                  return EventCalendar(events: events, onOpen: _open);
                }
                if (events.isEmpty) {
                  return Center(
                    child: BrutEmptyState(
                      icon: Icons.filter_alt_outlined,
                      title: 'Nothing ${_status.label.toLowerCase()}',
                      hint: 'Tap All to see every proposal again.',
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => app.refreshList(app.loadEvents),
                  child: ListView(
                    // Always scrollable, so a short list can still be
                    // pulled: a one-event list is exactly when someone
                    // wonders whether anything has arrived.
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      for (final event in events) ...[
                        _EventCard(event: event),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// List or month. Two states, so a segmented pair rather than a menu —
/// and the selected one is filled rather than merely outlined, because an
/// outline is what every other control on this screen already wears.
/// Picks the order. A menu rather than a row of buttons: four orders
/// would take as much of the header as the title, and only one of them
/// is in force at a time.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onChanged});

  final _EventSort sort;
  final ValueChanged<_EventSort> onChanged;

  Future<void> _choose(BuildContext context) async {
    final picked = await showFloatingPeek<_EventSort>(
      context,
      title: 'Sort events',
      subtitle: sort.label,
      child: _SortChoices(current: sort),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return BrutIconButton(
      icon: Icons.swap_vert,
      label: 'Sort events, currently ${sort.label}',
      // Marked when it is not the default, so a list in an unexpected
      // order says so rather than looking wrong.
      tone: sort == _EventSort.dateAsc ? BrutTone.neutral : BrutTone.dark,
      size: 36,
      onPressed: () => _choose(context),
    );
  }
}

class _SortChoices extends StatelessWidget {
  const _SortChoices({required this.current});

  final _EventSort current;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in _EventSort.values) ...[
          BrutButton(
            label: option.label,
            icon: option == current ? Icons.check : option.icon,
            tone: option == current ? BrutTone.brand : BrutTone.neutral,
            onPressed: () => Navigator.of(context).pop(option),
          ),
          if (option != _EventSort.values.last)
            const SizedBox(height: AppLayout.tight),
        ],
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.calendar, required this.onChanged});

  final bool calendar;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrutIconButton(
          icon: Icons.view_agenda_outlined,
          label: 'List view',
          tone: calendar ? BrutTone.neutral : BrutTone.dark,
          size: 36,
          onPressed: () => onChanged(false),
        ),
        const SizedBox(width: 6),
        BrutIconButton(
          icon: Icons.calendar_month_outlined,
          label: 'Calendar view',
          tone: calendar ? BrutTone.dark : BrutTone.neutral,
          size: 36,
          onPressed: () => onChanged(true),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventItem event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final tone = eventStatusTone(event.status);

    return BrutCard(
      radius: AppRadius.rowAll,
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
      ),
      // The same hold-to-look the dashboard tile has: where this one
      // has got to, without opening it.
      onLongPress: () => showFloatingPeek(
        context,
        title: event.title,
        subtitle: event.statusLabel,
        openLabel: 'Open this event',
        onOpen: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
        ),
        child: EventProgressPeek(events: [event]),
      ),
      // The stripe stretches, so the row needs a height before it is laid
      // out — inside a list it has none, and `stretch` alone asks for an
      // infinite one.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The status as a stripe down the edge, so a long list can be
            // read by colour before any of it is read by word.
            Container(
              width: 8,
              decoration: BoxDecoration(
                color: tone.fill(context),
                border: Border(right: context.side),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadius.row - AppBorders.width),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Both of these are as long as their content, and
                    // "Waiting on the SDS Office" beside a full date
                    // ran off the right of a 411pt phone. The badge
                    // gives way first: the date is short and fixed,
                    // and a clipped date is worse than a clipped
                    // status that the colour already tells you.
                    Row(
                      children: [
                        Flexible(
                          child: BrutBadge(
                            label: event.statusLabel,
                            tone: tone,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Spacer(),
                        Text(event.date, style: AppText.moneySmall),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(event.title, style: AppText.cardTitle),
                    const SizedBox(height: 3),
                    Text(
                      event.org.isEmpty ? 'No organization' : event.org,
                      style: AppText.caption,
                    ),
                    const SizedBox(height: 6),
                    // School year / semester / scope. A legacy row missing
                    // them says so rather than showing a blank line, since
                    // an administrator has to repair it before it appears in
                    // academic reports.
                    if (event.hasIncompleteAcademicMetadata)
                      BrutBadge(
                        label: event.academicLabel,
                        tone: BrutTone.sun,
                        mono: true,
                      )
                    else
                      MonoLabel(event.academicLabel),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// School-year filter.
///
/// These are the only two real server-side filters on `GET /events`, so
/// they reload rather than filtering the loaded list — and the bar is
/// labelled so it is clear which narrowing is the server's.
/// "Needs school year" is the repair queue for legacy rows and is only
/// useful to an administrator, who is the one who can fix them.
/// What the list is narrowed to.
///
/// Status first, because that is how the list is actually read — the
/// stripe down each card is the same information, and the chips are how
/// you ask for one colour's worth of it.
///
/// School year sits behind it and only appears when there is a choice to
/// make: one year on its own is a chip that cannot change anything.
/// "Missing school year" is not a year at all — it is the repair queue
/// for legacy rows, and only an administrator can fix one.
class _EventFilterBar extends StatelessWidget {
  const _EventFilterBar({required this.status, required this.onStatus});

  final _StatusFilter status;
  final ValueChanged<_StatusFilter> onStatus;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final years = app.knownSchoolYears;
    final canRepair =
        !context.watch<AppState>().isOfflineViewing &&
        (app.currentRole?.isAdministrator ?? false);
    final showYears = years.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutChipBar(
          children: [
            for (final option in _StatusFilter.values)
              BrutChip(
                label: option.label,
                selected: option == status,
                tone: option.tone,
                onTap: () => onStatus(option),
              ),
          ],
        ),
        if (showYears || canRepair) ...[
          const SizedBox(height: 8),
          BrutChipBar(
            children: [
              if (showYears) ...[
                BrutChip(
                  label: 'All years',
                  selected:
                      app.schoolYearFilter == null &&
                      !app.showOnlyMissingSchoolYear,
                  onTap: () => app.applyEventFilter(),
                ),
                for (final year in years)
                  BrutChip(
                    label: year,
                    selected: app.schoolYearFilter == year,
                    onTap: () => app.applyEventFilter(schoolYear: year),
                  ),
              ],
              if (canRepair)
                BrutChip(
                  label: 'Missing school year',
                  selected: app.showOnlyMissingSchoolYear,
                  onTap: () => app.showOnlyMissingSchoolYear
                      ? app.applyEventFilter()
                      : app.applyEventFilter(missingOnly: true),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The colours the list is already sorted by, as something you can ask
/// for. Pending covers all three waiting stages: to the person reading
/// the list they mean one thing, and the badge says which desk.
/// How the list is ordered.
///
/// Only the list: the month view is already ordered by the calendar,
/// and sorting it would mean nothing.
enum _EventSort {
  dateAsc('Soonest first', Icons.arrow_upward),
  dateDesc('Latest first', Icons.arrow_downward),
  title('By name', Icons.sort_by_alpha),
  status('By status', Icons.flag_outlined);

  const _EventSort(this.label, this.icon);

  final String label;
  final IconData icon;

  /// An event with no date sorts to the end either way round, rather
  /// than to whichever end null happens to fall on.
  int compare(EventItem a, EventItem b) => switch (this) {
    _EventSort.dateAsc => _byDate(a, b),
    _EventSort.dateDesc => -_byDate(a, b),
    _EventSort.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    _EventSort.status => a.status.index.compareTo(b.status.index),
  };

  static int _byDate(EventItem a, EventItem b) {
    if (a.on == null && b.on == null) return 0;
    if (a.on == null) return 1;
    if (b.on == null) return -1;
    return a.on!.compareTo(b.on!);
  }
}

enum _StatusFilter {
  all('All', null),
  pending('Waiting', BrutTone.sun),
  approved('Approved', BrutTone.mint),
  rejected('Rejected', BrutTone.coral),
  draft('Drafts', BrutTone.neutral);

  const _StatusFilter(this.label, this.tone);

  final String label;
  final BrutTone? tone;

  bool matches(EventApprovalStatus status) => switch (this) {
    _StatusFilter.all => true,
    _StatusFilter.pending => status.isPending,
    _StatusFilter.approved =>
      status == EventApprovalStatus.approved ||
          status == EventApprovalStatus.completed,
    _StatusFilter.rejected => status == EventApprovalStatus.rejected,
    _StatusFilter.draft => status == EventApprovalStatus.draft,
  };
}
