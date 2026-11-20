import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';
import 'package:smartevent/widgets/outcome.dart';

/// The modal that says how something went.
///
/// Asked for as "we should add some of those confirmation status pop
/// ups", from reference images showing a success card, a publishing
/// card and a problem card with Try again.
void main() {
  /// BrutSpinner reads reduce-motion from AppSettings, which the app
  /// always has above it.
  Widget host(Widget Function(BuildContext) body) => ChangeNotifierProvider(
    create: (_) => AppSettings(),
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Builder(builder: (context) => Scaffold(body: body(context))),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> open(WidgetTester tester, Widget sheet) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        (context) => Center(
          child: TextButton(
            onPressed: () =>
                BrutSheet.show<void>(context, builder: (_) => sheet),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  testWidgets('the waiting state offers nothing to press', (tester) async {
    await open(
      tester,
      const OutcomeSheet(kind: OutcomeKind.working, title: 'Sending'),
    );

    expect(find.text('Sending'), findsOneWidget);
    expect(find.byType(BrutSpinner), findsOneWidget);
    // Nothing has happened yet, so there is nothing to acknowledge.
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('back does not close it while the work is running', (
    tester,
  ) async {
    await open(
      tester,
      const OutcomeSheet(kind: OutcomeKind.working, title: 'Sending'),
    );

    // Dismissing the sheet would not stop a request already in flight,
    // and a closed sheet would leave the person believing it had.
    await tester.binding.handlePopRoute();
    await settle(tester);

    expect(
      find.text('Sending'),
      findsOneWidget,
      reason: 'back dismissed a sheet that was still working',
    );
  });

  testWidgets('a finished sheet closes on Close', (tester) async {
    await open(
      tester,
      const OutcomeSheet(
        kind: OutcomeKind.done,
        title: 'Sent for department review.',
        body: 'The Moderator sees it first.',
      ),
    );

    expect(find.text('Sent for department review.'), findsOneWidget);
    expect(find.text('The Moderator sees it first.'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await settle(tester);

    expect(find.text('Sent for department review.'), findsNothing);
  });

  testWidgets('a problem offers the way out, and runs it after closing', (
    tester,
  ) async {
    var retried = false;
    await open(
      tester,
      OutcomeSheet(
        kind: OutcomeKind.problem,
        title: 'It was not sent',
        body: 'The server refused it.',
        actionLabel: 'Try again',
        onAction: () => retried = true,
      ),
    );

    expect(find.text('It was not sent'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await settle(tester);

    // The sheet goes first: the action usually opens something of its
    // own, and it would open behind this one.
    expect(find.text('It was not sent'), findsNothing);
    expect(retried, isTrue);
  });

  group('runWithOutcome', () {
    testWidgets('waits, then reports that it went through', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 900);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          (context) => Center(
            child: TextButton(
              onPressed: () => runWithOutcome<int>(
                context,
                // Long enough that the waiting sheet can be caught
                // on screen before the result replaces it.
                work: () async {
                  await Future<void>.delayed(const Duration(seconds: 2));
                  return 7;
                },
                working: 'Exporting',
                done: 'Exported',
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Exporting'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await settle(tester);

      // The waiting sheet is replaced, not stacked under the result.
      expect(find.text('Exporting'), findsNothing);
      expect(find.text('Exported'), findsOneWidget);
    });

    testWidgets('a thrown failure becomes the problem sheet', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 900);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          (context) => Center(
            child: TextButton(
              onPressed: () => runWithOutcome<void>(
                context,
                work: () async => throw Exception('no network'),
                working: 'Exporting',
                done: 'Exported',
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await settle(tester);

      expect(find.text('Exported'), findsNothing);
      // The thrown message is shown: the API layer writes those for
      // people, not for logs.
      expect(find.textContaining('no network'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
