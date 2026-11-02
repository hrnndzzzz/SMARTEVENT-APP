import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/events_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// The two ways of reading the events list.
///
/// The list went untested for long enough to grow a layout bug that only
/// appeared once it had rows in it, so both views are rendered here with
/// real events rather than against an empty state.
AppState _seeded() {
  final app = AppState()..devQuickLogin(UserRole.treasurer);
  final now = DateTime.now();
  DateTime day(int d) => DateTime(now.year, now.month, d);
  app.events.addAll([
    EventItem(
      title: 'CITE Week Opening',
      org: 'ICpEP.SE',
      date: '',
      on: day(6),
      budget: '₱18,000.00',
      status: EventApprovalStatus.approved,
    ),
    EventItem(
      title: 'Hackathon 2026',
      org: 'ICpEP.SE',
      date: '',
      on: day(14),
      budget: '₱42,500.00',
      status: EventApprovalStatus.pendingAdmin,
    ),
    EventItem(
      title: 'Capstone Defense Snacks',
      org: '',
      date: 'No date set',
      budget: '₱1,800.00',
      status: EventApprovalStatus.draft,
    ),
  ]);
  return app;
}

Widget _host(AppState app) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: app),
    ChangeNotifierProvider(create: (_) => AppSettings()),
    ChangeNotifierProvider(create: (_) => Reachability()),
  ],
  child: MaterialApp(theme: AppTheme.light(), home: const EventsScreen()),
);

/// A phone-shaped surface, taller than the 800x600 default: the calendar
/// puts the agenda under a six-row grid, and a list view never builds the
/// children it cannot see.
Future<void> _open(WidgetTester tester, AppState app) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 1200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(app));
  await tester.pump();
}

Future<void> _toCalendar(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Calendar view'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('the list renders its rows', (tester) async {
    await _open(tester, _seeded());

    expect(find.text('CITE Week Opening'), findsOneWidget);
    expect(find.text('Hackathon 2026'), findsOneWidget);
    // The one without a date belongs in the list, which is the view that
    // shows every event.
    expect(find.text('Capstone Defense Snacks'), findsOneWidget);
  });

  testWidgets('the calendar opens on this month and today', (tester) async {
    await _open(tester, _seeded());
    await _toCalendar(tester);

    final now = DateTime.now();
    expect(find.textContaining('${now.year}'), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('tapping a day shows what is on it', (tester) async {
    await _open(tester, _seeded());
    await _toCalendar(tester);

    // The 14th, by its number in the grid rather than by position.
    await tester.tap(find.widgetWithText(GestureDetector, '14').last);
    await tester.pump();

    expect(find.text('Hackathon 2026'), findsOneWidget);
    expect(find.text('CITE Week Opening'), findsNothing);
  });

  testWidgets('an event with no date is reported, not placed', (tester) async {
    await _open(tester, _seeded());
    await _toCalendar(tester);

    expect(find.textContaining('no date yet'), findsOneWidget);
    expect(find.text('Capstone Defense Snacks'), findsNothing);
  });

  testWidgets('the month steps and comes back', (tester) async {
    await _open(tester, _seeded());
    await _toCalendar(tester);

    expect(find.text('Back to today'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pump();
    // Off the current month, the way back has to be one tap.
    expect(find.text('Back to today'), findsOneWidget);

    await tester.tap(find.text('Back to today'));
    await tester.pump();
    expect(find.text('Back to today'), findsNothing);
  });

  testWidgets('status chips narrow both views', (tester) async {
    await _open(tester, _seeded());

    expect(find.text('CITE Week Opening'), findsOneWidget);
    expect(find.text('Hackathon 2026'), findsOneWidget);

    // Waiting leaves only the one with a pending status.
    await tester.tap(find.text('Waiting'));
    await tester.pump();
    expect(find.text('Hackathon 2026'), findsOneWidget);
    expect(find.text('CITE Week Opening'), findsNothing);

    // And the month honours the same narrowing.
    await _toCalendar(tester);
    expect(find.textContaining('1 this month'), findsNothing);
  });

  // `rejected` is the SDS Office's final decision, not a return: a return
  // puts the event back to a draft, which the Drafts chip already finds.
  testWidgets('the rejected chip is called rejected and finds rejections', (
    tester,
  ) async {
    final app = _seeded();
    await _open(tester, app);

    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Returned'), findsNothing);

    // The chip bar scrolls sideways, and this one starts off the edge.
    await tester.ensureVisible(find.text('Rejected'));
    await tester.pump();
    await tester.tap(find.text('Rejected'));
    await tester.pump();
    expect(find.text('Nothing rejected'), findsOneWidget);

    app.events.add(
      EventItem(
        title: 'Industry Immersion Talk',
        org: 'ACPES',
        date: '',
        budget: '₱8,000.00',
        status: EventApprovalStatus.rejected,
      ),
    );
    app.updateEvent();
    await tester.pump();

    expect(find.text('Industry Immersion Talk'), findsOneWidget);
    expect(find.text('Hackathon 2026'), findsNothing);
  });

  testWidgets('a single school year offers no year chip', (tester) async {
    await _open(tester, _seeded());
    // One year in the data is a chip that cannot change anything.
    expect(find.text('All years'), findsNothing);
  });
}
