import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';

/// A rejected proposal does not always know who rejected it — a legacy
/// row, or one seeded before the field existed, carries no reviewer. The
/// screen used to interpolate that straight into the sentence and print
/// "Rejected by null." on the card a reviewer reads first.
void main() {
  Widget host(EventItem event) {
    final app = AppState()..devQuickLogin(UserRole.treasurer);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => Reachability()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EventDetailScreen(event: event),
      ),
    );
  }

  EventItem rejected({String? by, String? note}) => EventItem(
    title: 'Alumni Homecoming Night',
    org: 'ICpEP.SE',
    date: '11/21/2026',
    budget: '₱5,000.00',
    status: EventApprovalStatus.rejected,
    rejectedBy: by,
    adminApprovalNote: note,
  );

  testWidgets('an unknown reviewer is not printed as null', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(rejected()));
    await tester.pump();

    expect(find.textContaining('null'), findsNothing);
    expect(find.textContaining('This proposal was rejected'), findsOneWidget);
  });

  testWidgets('a known reviewer is still named', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(rejected(by: 'Adviser')));
    await tester.pump();

    // Twice over: the status badge and the card below it.
    expect(find.textContaining('Rejected by Adviser'), findsWidgets);
    expect(find.textContaining('null'), findsNothing);
  });
}
