import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/state/app_state.dart';
import 'package:smartevent/state/user_role.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/widgets/event_calendar.dart';

/// A calendar inside a sheet.
///
/// The calendar is a ListView, which wants all the height there is, and
/// a sheet sizes itself to its content, which offers none. Put together
/// without a height between them, the planner opened blank.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a calendar in a sheet draws something', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final app = AppState()..enterDemo(role: UserRole.treasurer);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => BrutSheet.show<void>(
                    context,
                    builder: (sheetContext) => BrutSheet(
                      title: 'Planner',
                      child: SizedBox(
                        height:
                            MediaQuery.sizeOf(sheetContext).height * 0.62,
                        child: EventCalendar(events: app.events),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Planner'), findsOneWidget);
    expect(find.byType(EventCalendar), findsOneWidget);

    // The thing that was actually wrong: it had no height, so nothing
    // of it was on screen.
    final box = tester.getSize(find.byType(EventCalendar));
    expect(box.height, greaterThan(100), reason: 'the calendar is flat');
    expect(box.width, greaterThan(100));
  });

  testWidgets('and lays out without throwing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final app = AppState()..enterDemo(role: UserRole.treasurer);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: EventCalendar(events: app.events),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}
