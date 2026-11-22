import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/widgets/spotlight_tour.dart';

/// The first-sign-in tour: one lit control at a time, Next and Skip, and
/// remembered per account so it shows once.
void main() {
  bool? result;

  Future<void> open(WidgetTester tester) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const TourSpot(
                  'first',
                  child: SizedBox(height: 60, width: 200),
                ),
                const TourSpot(
                  'second',
                  child: SizedBox(height: 60, width: 200),
                ),
                TextButton(
                  onPressed: () async =>
                      result = await showSpotlightTour(context, const [
                        TourStep('first', 'First', 'The first one.'),
                        // Never built, like the Record button for an Adviser.
                        TourStep('absent', 'Absent', 'Not on screen.'),
                        TourStep('second', 'Second', 'The second one.'),
                      ]),
                  child: const Text('Start'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
  }

  testWidgets('steps through what is on screen and skips what is not', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('1 OF 2'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('2 OF 2'), findsOneWidget);
    expect(find.text('Absent'), findsNothing);
    expect(find.text('Skip'), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    expect(result, isTrue);
  });

  testWidgets('Skip closes it from the first step', (tester) async {
    await open(tester);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('1 OF 2'), findsNothing);
    expect(result, isFalse);
  });

  test('is remembered per account on this phone', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    expect(await settings.tourSeen('ana'), isFalse);
    await settings.markTourSeen('ana');
    expect(await settings.tourSeen('ana'), isTrue);
    expect(await settings.tourSeen('ben'), isFalse);
  });
}
