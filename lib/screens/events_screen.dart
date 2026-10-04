import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import 'notifications_screen.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';

/// One mapping from approval status to meaning, used for the badge and
/// the stripe alike so the two can never disagree.
///
/// Draft is deliberately the quietest: it is nobody's queue yet. Completed
/// reads like approved, since it is the settled end state. Both pending
/// stages are yellow — they mean the same thing to the person looking at
/// the list, and the label says which desk it is on.
BrutTone eventStatusTone(EventApprovalStatus s) => switch (s) {
  EventApprovalStatus.draft => BrutTone.neutral,
  EventApprovalStatus.approved ||
  EventApprovalStatus.completed => BrutTone.mint,
  EventApprovalStatus.rejected => BrutTone.coral,
  EventApprovalStatus.pendingAdmin ||
  EventApprovalStatus.pendingAdviser => BrutTone.sun,
};

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BrutScreen(
      topBar: AppHeader(
        onBellTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      ),
      scrollable: false,
      bottomPadding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Events', style: AppText.screenTitle)),
              // Officers are read-only and SDS has no event access, so
              // only roles that may actually propose get this.
              if (context.watch<AppState>().currentRole?.canProposeEvents ??
                  false)
                BrutButton(
                  label: 'New',
                  icon: Icons.add,
                  size: BrutSize.small,
                  expand: false,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CreateEventScreen(),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const _SchoolYearFilterBar(),
          const SizedBox(height: 12),
          Expanded(
            child: Consumer<AppState>(
              builder: (context, app, _) {
                if (app.eventsLoad.isLoading && app.events.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
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
                          : (app.currentRole?.canProposeEvents ?? false)
                          ? 'Tap New to submit one.'
                          : null,
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final event in app.events) ...[
                      _EventCard(event: event),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
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
                  Row(
                    children: [
                      BrutBadge(label: event.statusLabel, tone: tone),
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
class _SchoolYearFilterBar extends StatelessWidget {
  const _SchoolYearFilterBar();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final years = app.knownSchoolYears;
    final canRepair = app.currentRole?.isAdministrator ?? false;

    if (years.isEmpty && !canRepair) return const SizedBox.shrink();

    return BrutChipBar(
      children: [
        BrutChip(
          label: 'All years',
          selected:
              app.schoolYearFilter == null && !app.showOnlyMissingSchoolYear,
          onTap: () => app.applyEventFilter(),
        ),
        for (final year in years)
          BrutChip(
            label: year,
            selected: app.schoolYearFilter == year,
            onTap: () => app.applyEventFilter(schoolYear: year),
          ),
        if (canRepair)
          BrutChip(
            label: 'Needs school year',
            selected: app.showOnlyMissingSchoolYear,
            onTap: () => app.applyEventFilter(missingOnly: true),
          ),
      ],
    );
  }
}
