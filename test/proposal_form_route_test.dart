import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/event_detail_screen.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/reachability.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// The app rebuilds `MaterialApp` on every AppState change (main.dart), and
/// the Navigator then re-runs every route's builder. A form made inside the
/// builder was replaced by a fresh one that never loaded, so Part 1 saved
/// with `expected_version: 0` and a blank department.
void main() {
  testWidgets('the proposal form survives an app rebuild', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.reset);

    final app = AppState()..enterDemo(role: UserRole.treasurer);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider(create: (_) => AppSettings()),
          ChangeNotifierProvider(create: (_) => Reachability()),
        ],
        // As main.dart does it.
        child: Consumer<AppState>(
          builder: (_, _, _) => MaterialApp(
            theme: AppTheme.light(),
            home: EventDetailScreen(
              event: EventItem(
                remoteId: 'e1',
                title: 'Programming Bootcamp',
                org: 'ACPES',
                date: '11/21/2026',
                budget: '₱5,000.00',
                status: EventApprovalStatus.draft,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final open = find.widgetWithText(BrutButton, 'Proposal form');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    final form = tester.widget<SapFormScreen>(find.byType(SapFormScreen)).form;

    app.switchDemoRole(UserRole.adviser); // any AppState change
    await tester.pumpAndSettle();

    expect(
      tester.widget<SapFormScreen>(find.byType(SapFormScreen)).form,
      same(form),
    );
  });
}
