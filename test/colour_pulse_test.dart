import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/widgets/colour_pulse.dart';

/// The flourish the wordmark does when it is already home.
void main() {
  test('it picks from the accents', () {
    for (var i = 0; i < 50; i++) {
      expect(ColourPulse.palette, contains(ColourPulse.pick()));
    }
  });

  test('and never the one it is told to avoid', () {
    for (final colour in ColourPulse.palette) {
      for (var i = 0; i < 30; i++) {
        expect(ColourPulse.pick(avoiding: colour), isNot(colour));
      }
    }
  });

  test('and it varies, rather than being the same joke twice', () {
    final seen = {for (var i = 0; i < 400; i++) ColourPulse.pick()};
    expect(seen.length, greaterThan(1));
  });

  testWidgets('it leaves nothing behind', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ColourPulse.show(context),
                child: const Text('pulse'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('pulse'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // The overlay entry removes itself when the animation ends; if it
    // did not, this would still be running and pumpAndSettle would have
    // timed out above.
    expect(find.text('pulse'), findsOneWidget);
  });

  testWidgets('and does nothing at all when motion is turned down', (
    tester,
  ) async {
    // Somebody who asked the system to stop things moving has not asked
    // for a flashing screen.
    bool? ran;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => ran = ColourPulse.show(context),
                  child: const Text('pulse'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('pulse'));
    await tester.pumpAndSettle();

    expect(ran, isFalse);
  });
}
