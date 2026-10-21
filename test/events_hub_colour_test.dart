import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/screens/events_hub_screen.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/user_role.dart';
import 'package:smartevent/theme/app_colors.dart';
import 'package:smartevent/theme/app_theme.dart';

/// The create band is a button. Its colour must not depend on what
/// happened to the last event, or it changes under people.
Future<Color> bandColour(WidgetTester tester, EventApprovalStatus status) async {
  final app = AppState()..enterDemo(role: UserRole.treasurer);
  for (final event in app.events) {
    event.status = status;
  }

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const EventsHubScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final box = tester.widget<DecoratedBox>(
    find.byType(DecoratedBox).first,
  );
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('the create band holds one colour across every status', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));

    final seen = <Color>{};
    for (final status in EventApprovalStatus.values) {
      seen.add(await bandColour(tester, status));
    }

    expect(
      seen,
      hasLength(1),
      reason: 'the band changed colour with the event status',
    );
    // Named, so the test cannot pass by having found some other box
    // that happens never to change.
    expect(
      seen.single,
      AppColors.brand,
      reason: 'the create band should be the app\'s blue',
    );
  });
}
