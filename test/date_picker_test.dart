import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/widgets/brut_date_picker.dart';

/// The app's own date picker.
///
/// It replaced Material's, which arrived with its own radii and ripples
/// and was the one moment the app stopped looking like itself. The rules
/// it has to keep are the ones the backend also enforces: a proposal is
/// for a day that has not happened yet.
void main() {
  Future<DateTime?> open(
    WidgetTester tester, {
    required DateTime first,
    required DateTime last,
    DateTime? initial,
  }) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await BrutDatePicker.show(
                    context,
                    initial: initial,
                    firstDate: first,
                    lastDate: last,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return result;
  }

  testWidgets('opens on the month of the earliest allowed day', (tester) async {
    await open(
      tester,
      first: DateTime(2026, 3, 10),
      last: DateTime(2027, 3, 10),
    );
    expect(find.text('March 2026'), findsOneWidget);
  });

  testWidgets('cannot step behind the first month', (tester) async {
    await open(
      tester,
      first: DateTime(2026, 3, 10),
      last: DateTime(2027, 3, 10),
    );

    await tester.tap(find.bySemanticsLabel('Previous month'));
    await tester.pump();
    expect(find.text('March 2026'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pump();
    expect(find.text('April 2026'), findsOneWidget);
  });

  testWidgets('a day before the first is refused', (tester) async {
    await open(
      tester,
      first: DateTime(2026, 3, 10),
      last: DateTime(2027, 3, 10),
    );

    // Nothing is chosen yet, so the action says so and does nothing.
    expect(find.text('Pick a day'), findsOneWidget);

    await tester.tap(find.text('5'));
    await tester.pump();
    expect(find.text('Pick a day'), findsOneWidget);

    await tester.tap(find.text('12'));
    await tester.pump();
    expect(find.text('Use 12 March'), findsOneWidget);
  });

  testWidgets('it hands back the day that was picked', (tester) async {
    DateTime? picked;
    await tester.runAsync(() async {});
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await BrutDatePicker.show(
                    context,
                    firstDate: DateTime(2026, 3, 10),
                    lastDate: DateTime(2027, 3, 10),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('12'));
    await tester.pump();
    await tester.tap(find.text('Use 12 March'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(picked, DateTime(2026, 3, 12));
  });
}
