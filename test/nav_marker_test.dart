import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/widgets/page_indicator.dart';

/// The marker under the chosen destination is a flat block.
///
/// It used to be a gradient that held the outside edge of the bar and
/// faded towards the middle — a second thing for the eye to resolve on
/// a control whose whole job is to say which of three places you are
/// in. Everything else in the app is a flat fill with a hard edge.
///
/// This replaces the test that checked the fade, which is why it
/// checks the absence of one: a gradient is easy to reintroduce by
/// copying a decoration from somewhere else, and nothing else here
/// would notice.
void main() {
  Future<void> pump(WidgetTester tester, int current) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: PageIndicator(
          current: current,
          labels: const ['Menu', 'Dashboard', 'Events'],
          onGo: (_) {},
        ),
      ),
    ),
  );

  List<BoxDecoration> markers(WidgetTester tester) => [
    for (final container in tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    ))
      if (container.decoration case final BoxDecoration d) d,
  ];

  testWidgets('nothing in the bar is a gradient', (tester) async {
    await pump(tester, 1);
    final found = markers(tester);
    expect(found, isNotEmpty, reason: 'no markers were found to check');
    for (final decoration in found) {
      expect(decoration.gradient, isNull);
    }
  });

  testWidgets('exactly one destination is filled, and it is the current one', (
    tester,
  ) async {
    for (final current in [0, 1, 2]) {
      await pump(tester, current);
      final filled = markers(tester).where((d) => d.color != null).toList();
      expect(
        filled,
        hasLength(1),
        reason: 'page $current should fill one marker and only one',
      );
      // Flat means one colour, at full strength — not a wash of it.
      expect(filled.single.color!.a, 1.0);
    }
  });

  testWidgets('and the fill is the department accent it was given', (
    tester,
  ) async {
    const accent = Color(0xFFE27031);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(accent: accent),
        home: const Scaffold(
          body: PageIndicator(
            current: 0,
            labels: ['Menu', 'Dashboard', 'Events'],
            onGo: _nothing,
          ),
        ),
      ),
    );
    final filled = markers(tester).where((d) => d.color != null).single;
    expect(filled.color, accent);
  });
}

void _nothing(int _) {}
