import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  // Draft is deliberately the quietest: it is nobody's queue yet.
  // Completed reads like approved, since it is the settled end state.
  Color _statusBg(EventApprovalStatus s) => switch (s) {
    EventApprovalStatus.draft => AppColors.trackBg,
    EventApprovalStatus.approved ||
    EventApprovalStatus.completed => AppColors.sageTealTint,
    EventApprovalStatus.rejected => const Color(0xFFFBEAE7),
    EventApprovalStatus.pendingAdmin => AppColors.marigoldTint,
    EventApprovalStatus.pendingAdviser => const Color(0xFFEDEBE6),
  };

  Color _statusColor(EventApprovalStatus s) => switch (s) {
    EventApprovalStatus.draft => AppColors.inkFaint,
    EventApprovalStatus.approved ||
    EventApprovalStatus.completed => AppColors.sageTealText,
    EventApprovalStatus.rejected => AppColors.brick,
    EventApprovalStatus.pendingAdmin => AppColors.marigoldText,
    EventApprovalStatus.pendingAdviser => AppColors.inkMuted,
  };

  Color _tagColor(EventApprovalStatus s) => switch (s) {
    EventApprovalStatus.draft => AppColors.inkFaint,
    EventApprovalStatus.approved ||
    EventApprovalStatus.completed => AppColors.sageTeal,
    EventApprovalStatus.rejected => AppColors.brick,
    EventApprovalStatus.pendingAdmin => AppColors.marigold,
    EventApprovalStatus.pendingAdviser => AppColors.inkFaint,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Events',
                    style: TextStyle(
                      fontFamily: AppText.headerFamily,
                      fontWeight: FontWeight.w500,
                      fontSize: 18,
                      color: AppColors.ink,
                    ),
                  ),
                  // Officers are read-only and SDS has no event access, so
                  // only roles that may actually propose get this.
                  if (context.watch<AppState>().currentRole?.canProposeEvents ??
                      false)
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CreateEventScreen()),
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const _SchoolYearFilterBar(),
              const SizedBox(height: 10),
              Expanded(
                child: Consumer<AppState>(
                  builder: (context, app, _) {
                    if (app.eventsLoad.isLoading && app.events.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (app.eventsLoad.hasFailed && app.events.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                app.eventsLoad.error!,
                                style: AppText.caption,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: app.loadEvents,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (app.events.isEmpty) {
                      return Center(
                        child: Text(
                          app.schoolYearFilter != null ||
                                  app.showOnlyMissingSchoolYear
                              // An active filter is a far likelier reason
                              // for an empty list than there being none.
                              ? 'No events match this filter.'
                              : (app.currentRole?.canProposeEvents ?? false)
                                  ? 'No events yet. Tap "New" to submit one.'
                                  : 'No events yet.',
                          style: AppText.caption,
                        ),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        for (final event in app.events) ...[
                          _EventCard(
                            event: event,
                            statusBg: _statusBg(event.status),
                            statusColor: _statusColor(event.status),
                            tagColor: _tagColor(event.status),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventItem event;
  final Color statusBg;
  final Color statusColor;
  final Color tagColor;

  const _EventCard({
    required this.event,
    required this.statusBg,
    required this.statusColor,
    required this.tagColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(event: event),
        ),
      ),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border, width: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        event.statusLabel,
                        style: TextStyle(
                          fontFamily: AppText.bodyFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: statusColor,
                        ),
                      ),
                    ),
                    Text(
                      event.date,
                      style: const TextStyle(
                        fontFamily: AppText.monoFamily,
                        fontSize: 11,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(event.title, style: AppText.cardTitle),
                const SizedBox(height: 2),
                Text('${event.org} · ${event.attendees}', style: AppText.caption),
                const SizedBox(height: 2),
                // School year / semester / scope. A legacy row missing them
                // says so rather than showing a blank line, since an
                // administrator has to repair it before it appears in
                // academic reports.
                Text(
                  event.academicLabel,
                  style: TextStyle(
                    fontFamily: AppText.bodyFamily,
                    fontSize: 10,
                    color: event.hasIncompleteAcademicMetadata
                        ? AppColors.marigoldText
                        : AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 12,
            bottom: 12,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: tagColor,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
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

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChip(
            label: 'All years',
            selected: app.schoolYearFilter == null && !app.showOnlyMissingSchoolYear,
            onTap: () => app.applyEventFilter(),
          ),
          for (final year in years)
            _FilterChip(
              label: year,
              selected: app.schoolYearFilter == year,
              onTap: () => app.applyEventFilter(schoolYear: year),
            ),
          if (canRepair)
            _FilterChip(
              label: 'Needs school year',
              selected: app.showOnlyMissingSchoolYear,
              onTap: () => app.applyEventFilter(missingOnly: true),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.indigo : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.indigo : AppColors.border,
            ),
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
      ),
    );
  }
}
