import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'create_event_screen.dart';
import 'event_approvals_screen.dart';
import 'events_screen.dart';

/// Events, one swipe left of the dashboard.
///
/// Three bands, because there are exactly three things anyone does with
/// an event: propose one, look through them, or find out where one got
/// to. Each fills a third of the screen, so none of them is the small
/// one you have to hunt for.
///
/// The first band carries the state of the newest proposal in its
/// colour — yellow while someone is deciding, coral if it came back,
/// green once it is through. Before you read a word, the screen has
/// already told you whether anything needs you.
class EventsHubScreen extends StatelessWidget {
  const EventsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final role = app.currentRole;
    final canPropose = role?.canProposeEvents ?? false;

    final latest = app.events.isEmpty ? null : app.events.first;
    final pending = app.events.where((e) => e.status.isPending).length;

    return Scaffold(
      backgroundColor: context.palette.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppLayout.gutter,
                AppLayout.contentPadding,
                AppLayout.gutter,
                AppLayout.between,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonoLabel('${app.events.length} on record'),
                  const SizedBox(height: 2),
                  const Text('Events', style: AppText.display),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _CreateBand(canPropose: canPropose, latest: latest),
                  ),
                  Expanded(
                    child: _Band(
                      index: 2,
                      title: 'All events',
                      blurb: 'Every proposal, filtered by school year',
                      icon: Icons.list_alt_outlined,
                      // Not brand: band one is brand before anything has
                      // been proposed, and two blue bands touching read
                      // as one band.
                      tone: BrutTone.violet,
                      count: app.events.length,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EventsScreen()),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Band(
                      index: 3,
                      title: 'Approvals',
                      blurb: 'Where each one got to, and who decided',
                      icon: Icons.fact_check_outlined,
                      tone: pending > 0 ? BrutTone.sun : BrutTone.teal,
                      count: pending,
                      countLabel: pending > 0 ? 'waiting' : null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EventApprovalsScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Band one. It is the create button for whoever may propose, and the
/// state of the newest proposal for everyone else — an Officer has no
/// create button anywhere in this app, and one here would only collect a
/// 403.
class _CreateBand extends StatelessWidget {
  const _CreateBand({required this.canPropose, required this.latest});

  final bool canPropose;
  final EventItem? latest;

  /// Null means nothing has been proposed yet, which is its own state —
  /// not a pending one, and not a finished one.
  (BrutTone, String, String) get _state {
    final event = latest;
    if (event == null) {
      return (
        BrutTone.brand,
        'Nothing proposed yet',
        canPropose ? 'Tap, or swipe up, to write the first one' : '',
      );
    }
    return switch (event.status) {
      EventApprovalStatus.draft => (
        BrutTone.neutral,
        'Draft — not submitted',
        event.title,
      ),
      EventApprovalStatus.pendingAdviser => (
        BrutTone.sun,
        'With the adviser',
        event.title,
      ),
      EventApprovalStatus.pendingAdmin => (
        BrutTone.sun,
        'With the admin',
        event.title,
      ),
      EventApprovalStatus.rejected => (
        BrutTone.coral,
        'Came back — needs changes',
        event.title,
      ),
      EventApprovalStatus.approved ||
      EventApprovalStatus.completed => (BrutTone.mint, 'Approved', event.title),
    };
  }

  void _open(BuildContext context) {
    if (!canPropose) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateEventScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final (tone, headline, detail) = _state;
    final fill = tone.fill(context);
    final on = context.foregroundOn(fill);

    return GestureDetector(
      onTap: () => _open(context),
      // Swipe up opens it too: the band is at the top of the screen, and
      // flicking it up is the shortest path from thumb to form.
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) _open(context);
      },
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: canPropose ? 'Create an event' : headline,
        button: canPropose,
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            border: Border(bottom: context.side),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppLayout.gutter,
            16,
            AppLayout.gutter,
            16,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _Numeral(value: 1, on: on),
                        const SizedBox(width: AppLayout.tight),
                        Expanded(
                          child: Text(
                            headline.toUpperCase(),
                            style: AppText.monoLabel.copyWith(color: on),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        canPropose ? 'Create\nevent' : 'Latest\nproposal',
                        style: AppText.display.copyWith(
                          fontSize: 34,
                          height: 1.0,
                          color: on,
                        ),
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        style: AppText.caption.copyWith(color: on),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
              const SizedBox(width: AppLayout.between),
              if (canPropose)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard_arrow_up, size: 24, color: on),
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: on, width: 2),
                      ),
                      child: Icon(Icons.add, size: 26, color: on),
                    ),
                  ],
                )
              else
                Icon(Icons.lock_outline, size: 24, color: on),
            ],
          ),
        ),
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({
    required this.index,
    required this.title,
    required this.blurb,
    required this.icon,
    required this.tone,
    required this.onTap,
    this.count,
    this.countLabel,
  });

  final int index;
  final String title;
  final String blurb;
  final IconData icon;
  final BrutTone tone;
  final VoidCallback onTap;
  final int? count;
  final String? countLabel;

  @override
  Widget build(BuildContext context) {
    final fill = tone.fill(context);
    final on = context.foregroundOn(fill);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: title,
        button: true,
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            border: Border(bottom: context.side),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppLayout.gutter,
            16,
            AppLayout.gutter,
            16,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _Numeral(value: index, on: on),
                        const SizedBox(width: AppLayout.tight),
                        if (count != null && count! > 0)
                          Text(
                            countLabel == null
                                ? '$count'
                                : '$count ${countLabel!}'.toUpperCase(),
                            style: AppText.monoLabel.copyWith(color: on),
                          ),
                      ],
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: AppText.display.copyWith(
                          fontSize: 32,
                          height: 1.0,
                          color: on,
                        ),
                      ),
                    ),
                    Text(
                      blurb,
                      style: AppText.caption.copyWith(color: on),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppLayout.between),
              Icon(icon, size: 26, color: on),
              const SizedBox(width: AppLayout.tight),
              Icon(Icons.arrow_outward, size: 22, color: on),
            ],
          ),
        ),
      ),
    );
  }
}

class _Numeral extends StatelessWidget {
  const _Numeral({required this.value, required this.on});

  final int value;
  final Color on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: on, width: 1.5),
      ),
      child: Text(
        '$value',
        style: AppText.number.copyWith(fontSize: 10, color: on),
      ),
    );
  }
}
