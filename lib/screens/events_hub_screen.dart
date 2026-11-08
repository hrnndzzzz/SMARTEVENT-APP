import 'package:flutter/material.dart';
import 'sap/sap_proposal_flow.dart';
import '../state/sap_form.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import 'events_screen.dart';

/// Events, one swipe left of the dashboard.
///
/// Two bands: propose one, or look through them. There used to be a
/// third for approvals, which turned out to be the list again with one
/// filter already applied — the list's own Waiting chip does the same
/// thing without a second screen to keep in step.
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
    final canPropose = app.mayProposeEvents;

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
                      blurb: pending > 0
                          ? '$pending waiting · list or month'
                          : 'Every proposal, as a list or a month',
                      icon: Icons.list_alt_outlined,
                      // Orange rather than blue: band one is blue before
                      // anything is proposed, and two blue bands touching
                      // read as one band.
                      tone: BrutTone.orange,
                      count: app.events.length,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EventsScreen()),
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
/// state of the newest proposal for anyone who may not propose (SDS
/// and signatories) — a create button would only collect a 403. While
/// the newest proposal is a draft, it is the way back into it. A
/// proposal waiting on a decision does not block a new one.
class _CreateBand extends StatelessWidget {
  const _CreateBand({required this.canPropose, required this.latest});

  final bool canPropose;
  final EventItem? latest;

  /// What the band says. Null means nothing has been proposed yet,
  /// which is its own state — not a pending one, and not a finished one.
  ///
  /// The colour is deliberately not part of this. This band is the
  /// create button, and a button that turns yellow, red or green
  /// depending on something that happened to a different event is a
  /// button nobody can learn. The status still shows, in words, where
  /// changing text costs nothing.
  (String, String) get _state {
    final event = latest;
    if (event == null) {
      return (
        'Nothing proposed yet',
        canPropose ? 'Tap, or swipe up, to write the first one' : '',
      );
    }
    return switch (event.status) {
      EventApprovalStatus.draft => ('Draft — not submitted', event.title),
      // In the wizard's own words. The band starts a proposal, and the
      // wizard says the Moderator, the Dean and the SDS Office.
      EventApprovalStatus.pendingAdviser => ('With the Moderator', event.title),
      EventApprovalStatus.pendingAdmin => ('With the Dean', event.title),
      EventApprovalStatus.pendingInstitutional => (
        'With the SDS Office',
        event.title,
      ),
      EventApprovalStatus.rejected => ('Rejected', event.title),
      EventApprovalStatus.approved ||
      EventApprovalStatus.completed => ('Approved', event.title),
    };
  }

  /// The newest event, when it is a draft to carry on with.
  EventItem? get _draft =>
      latest?.status == EventApprovalStatus.draft ? latest : null;

  /// Straight into the form. Filling it in is how an event gets made:
  /// the record is a consequence of Part 1, not a separate thing to ask
  /// for first. The event is created on the way out of that part, so
  /// nothing exists until there is a title and a date for it.
  ///
  /// A draft is the exception. The band names it, so tapping carries on
  /// with it, whoever in the organization began it, rather than starting
  /// a second proposal beside it.
  void _open(BuildContext context) {
    if (!canPropose) return;

    final app = context.read<AppState>();
    SapProposalFlow.start(
      context,
      SapForm(
        eventId: _draft?.remoteId,
        service: app.isDemoMode ? null : app.sapService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (headline, detail) = _state;
    final continues = _draft != null;
    final fill = BrutTone.brand.fill(context);
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
        label: canPropose
            ? (continues ? 'Continue the draft' : 'Create an event')
            : headline,
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
                        canPropose
                            ? (continues ? 'Continue\ndraft' : 'Create\nevent')
                            : 'Latest\nproposal',
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
  });

  final int index;
  final String title;
  final String blurb;
  final IconData icon;
  final BrutTone tone;
  final VoidCallback onTap;
  final int? count;

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
                            '$count',
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
