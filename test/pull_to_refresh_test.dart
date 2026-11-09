import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/theme/brut.dart';

/// Pull down to reload.
///
/// Six screens had the gesture and the rest did not, the dashboard
/// among them — and the six that had it only worked once the list was
/// long enough to scroll, which is the opposite of when anyone reaches
/// for it. A short list is exactly when you wonder whether anything has
/// arrived.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Future<void> Function()? onRefresh,
    double contentHeight = 40,
  }) => tester.pumpWidget(
    MaterialApp(
      home: BrutScreen(
        onRefresh: onRefresh,
        child: SizedBox(height: contentHeight, child: const Text('content')),
      ),
    ),
  );

  testWidgets('a screen given no handler keeps no indicator', (tester) async {
    await pump(tester, onRefresh: null);

    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets('a screen given one gets the gesture', (tester) async {
    await pump(tester, onRefresh: () async {});

    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets('a page too short to scroll can still be pulled', (
    tester,
  ) async {
    var refreshed = 0;
    await pump(
      tester,
      onRefresh: () async => refreshed++,
      // Far shorter than the viewport: without AlwaysScrollableScrollPhysics
      // this drag does nothing at all.
      contentHeight: 20,
    );

    await tester.fling(find.text('content'), const Offset(0, 320), 1000);
    await tester.pumpAndSettle();

    expect(
      refreshed,
      1,
      reason: 'the gesture must work before the list is long',
    );
  });

  testWidgets('the handler is not called without a pull', (tester) async {
    var refreshed = 0;
    await pump(tester, onRefresh: () async => refreshed++);
    await tester.pumpAndSettle();

    expect(refreshed, 0);
  });
}
