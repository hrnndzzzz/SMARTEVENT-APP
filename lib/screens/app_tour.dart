import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_areas.dart';
import '../state/app_state.dart';
import '../state/sap_form.dart';
import '../widgets/spotlight_tour.dart';
import 'sap/sap_proposal_flow.dart';

/// One screen of the tour: where it is, and what to say on it.
class _Leg {
  const _Leg(this.section, this.steps, {this.page, this.open});

  final String section;
  final List<TourStep> steps;

  /// A page of the shell to swipe to: 0 Menu, 1 Dashboard, 2 Events.
  final int? page;

  /// A screen to open on top of the shell.
  final void Function(BuildContext context)? open;
}

/// The whole walk-through, in one sitting: the dashboard, the Menu, each
/// module opened in turn, then the Events page, its list and the cover of
/// a new proposal. Skip or Back anywhere ends it; it always finishes on
/// the dashboard.
///
/// [showPage] moves the shell between its three pages, which only the
/// shell can do.
Future<void> runAppTour(
  BuildContext context, {
  required Future<void> Function(int page) showPage,
}) async {
  final app = context.read<AppState>();
  final navigator = Navigator.of(context);
  final proposes = app.mayProposeEvents && !app.lacksProposerAssignment;

  void push(String area) => unawaited(
    navigator.push(
      MaterialPageRoute<void>(builder: (c) => areaById(area)!.builder(c)),
    ),
  );

  final legs = [
    const _Leg('Dashboard', _dashboard, page: 1),
    const _Leg('Menu', _menu, page: 0),
    _Leg('Money', _money, open: (_) => push('money')),
    _Leg('Inventory', _inventory, open: (_) => push('inventory')),
    _Leg('Analytics', _analytics, open: (_) => push('reports')),
    _Leg('Flagged', _flagged, open: (_) => push('risk')),
    _Leg('Events', proposes ? _hubProposer : _hubReader, page: 2),
    _Leg('All events', _allEvents, open: (_) => push('events')),
    if (proposes)
      // A new form, never the draft the band would carry on with: the
      // cover saves nothing, and closing it leaves no event behind.
      _Leg(
        'Create event',
        _cover,
        open: (c) => SapProposalFlow.start(
          c,
          SapForm(service: app.isDemoMode ? null : app.sapService),
        ),
      ),
  ];

  for (final (i, leg) in legs.indexed) {
    if (!context.mounted) return;
    navigator.popUntil((route) => route.isFirst);
    if (leg.page case final page?) await showPage(page);
    if (!context.mounted) return;
    leg.open?.call(context);
    final carryOn = await showSpotlightTour(
      context,
      leg.steps,
      section: leg.section,
      more: i < legs.length - 1,
    );
    if (!carryOn) break;
  }
  if (!context.mounted) return;
  navigator.popUntil((route) => route.isFirst);
  await showPage(1);
}

const _dashboard = [
  TourStep(
    'dashboard.header',
    'Notices and your account',
    'The bell collects what is waiting on you. Tap your picture for '
        'your account and Settings.',
  ),
  TourStep(
    'dashboard.date',
    'The Planner',
    'Tap the date for every event with a date on it.',
  ),
  TourStep(
    'dashboard.budget',
    'What is left to spend',
    'The eye covers the figure from whoever is beside you. Tap any tile '
        'to open it, or hold it to peek without leaving.',
  ),
  TourStep(
    'shell.record',
    'Record an expense',
    'Scan a receipt and check what was read. Nothing is saved until you '
        'press Save.',
  ),
  TourStep(
    'shell.pages',
    'Three screens',
    'The Menu is to the left and Events to the right. Swipe, or tap one '
        'here. Settings can replay this tour.',
  ),
];

const _menu = [
  TourStep(
    'menu.grid',
    'Every module',
    'Each one shows what is waiting in it. Tap one to open it — the tour '
        'opens them in turn now.',
  ),
];

const _money = [
  TourStep(
    'money.figures',
    'Where the budget stands',
    'Allocated, spent, left and pending. Pending is the expenses waiting '
        'on a decision; tap it to see them.',
  ),
  TourStep(
    'money.record',
    'Record an expense',
    'The same as on the dashboard: scan a receipt, check it, save.',
  ),
  TourStep(
    'money.places',
    'Expenses, receipts, income, categories',
    'Each square opens its list. The number is how many are on record.',
  ),
];

const _inventory = [
  TourStep(
    'inventory.figures',
    'Stock at a glance',
    'How many items, where they are kept, and what is low or gone.',
  ),
  TourStep(
    'inventory.find',
    'Find an item',
    'Search by name, description or where it is kept. Sort it, or narrow '
        'it to one storage place.',
  ),
  TourStep(
    'inventory.move',
    'Record a movement',
    'Stock never changes by typing a new number. Tap here on an item to '
        'record what came in or went out.',
  ),
  TourStep(
    'inventory.new',
    'Add an item',
    'Items also arrive by completing a purchase. Add one by hand here.',
  ),
];

const _analytics = [
  TourStep(
    'reports.period',
    'Pick the period',
    'School year, semester, month or week. More filters chooses whose '
        'figures they are.',
  ),
  TourStep(
    'reports.tabs',
    'Three views',
    'Overview for the figures and charts, Events for each activity, '
        'Ledger for every line of money.',
  ),
  TourStep(
    'reports.download',
    'Download',
    'Save this report, or a snapshot of the dashboard.',
  ),
];

const _flagged = [
  TourStep(
    'risk.figures',
    'What is flagged',
    'How many, how many disagree with their receipt, what they are worth, '
        'and the largest.',
  ),
  TourStep(
    'risk.first',
    'A flagged expense',
    'Open it to see why. A flag is a prompt to look, not a finding.',
  ),
  TourStep(
    'risk.criteria',
    'What causes a flag',
    'A receipt that looks like another, or an amount that disagrees with '
        'its receipt. Clearing one is a reviewer decision, with a reason.',
  ),
];

const _hubProposer = [
  TourStep(
    'hub.create',
    'Create an event',
    'Tap, or swipe up, to start a proposal. While your newest one is a '
        'draft, this carries on with it instead.',
  ),
  TourStep('hub.all', 'All events', 'Every proposal, as a list or a month.'),
];

const _hubReader = [
  TourStep('hub.create', 'Your newest proposal', 'Where it has got to.'),
  TourStep('hub.all', 'All events', 'Every proposal, as a list or a month.'),
];

const _allEvents = [
  TourStep(
    'events.tools',
    'Order and view',
    'Change the order, or switch between the list and a month.',
  ),
  TourStep(
    'events.filters',
    'Filter',
    'Narrow the list to one status, or one school year.',
  ),
  TourStep(
    'events.new',
    'New event',
    'The same as Create event on the Events page.',
  ),
  TourStep(
    'events.first',
    'An event',
    'Tap to open it. Hold to peek without leaving the list.',
  ),
];

const _cover = [
  TourStep(
    'cover.dates',
    'Filled in for you',
    'The school year and the date of the proposal. Both can be changed on '
        'the first step.',
  ),
  TourStep(
    'cover.setting',
    'Where it is held',
    'On or off campus. It decides what the rest of the form asks for.',
  ),
  TourStep(
    'cover.start',
    'Start the form',
    'It opens once the setting is chosen. Nothing is made until you '
        'finish Part 1.',
  ),
];
