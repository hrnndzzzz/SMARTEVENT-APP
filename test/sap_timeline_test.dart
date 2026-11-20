import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/widgets/sap_timeline.dart';

/// Where a proposal has got to, drawn as the whole journey.
///
/// Asked for as "we should add those track status ui on applicable
/// features, like the part 1, part 2, part 3 status". The screen named
/// only the hand the proposal was in, which says nothing about what is
/// behind it or still to come.
void main() {
  Future<void> pump(
    WidgetTester tester,
    SapState state, {
    SapReturnedBy? by,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 1200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: SapTimeline(state: state)),
        ),
      ),
    );
    await tester.pump();
  }

  group('the stop it is standing at', () {
    test('every state maps to a stop, and the ends are the ends', () {
      // A switch with no default: a state added later fails to compile
      // rather than silently landing on stop one.
      for (final s in SapState.values) {
        final i = SapTimeline.indexFor(s);
        expect(i, greaterThanOrEqualTo(0));
        expect(i, lessThan(6));
      }
      expect(SapTimeline.indexFor(SapState.draft), 0);
      expect(SapTimeline.indexFor(SapState.completed), 5);
    });

    test('a return stands where it came back to, not where it was sent', () {
      // The office returned it *to the proposer*, so the proposal is
      // with the proposer. Marking it at the office would say the
      // office still has it.
      expect(
        SapTimeline.indexFor(SapState.revisionRequested),
        SapTimeline.indexFor(SapState.draft),
      );
    });

    test('a rejection stands at the office that made it', () {
      expect(
        SapTimeline.indexFor(SapState.rejected),
        SapTimeline.indexFor(SapState.pendingReview),
      );
    });
  });

  group('what it draws', () {
    testWidgets('it shows every stop, not only the current one', (
      tester,
    ) async {
      await pump(tester, SapState.pendingDepartmentReview);

      for (final name in [
        'Draft',
        'The department',
        'The SDS Office',
        'Signed',
        'Approved',
        'Completed',
      ]) {
        expect(find.text(name), findsOneWidget, reason: '$name is missing');
      }
      expect(find.text('STEP 2 / 6'), findsOneWidget);
    });

    testWidgets('a return says it came back, and nothing more', (tester) async {
      await pump(tester, SapState.revisionRequested);

      expect(find.text('Returned to you'), findsOneWidget);
      // It replaces that stop's usual line rather than sitting beside
      // it, or the stop would claim two things at once.
      expect(find.text('Yours to fill in'), findsNothing);
      // Who returned it and why belong to the banner below, which
      // carries the remarks too. Naming them here as well put the same
      // sentence on the screen twice.
      expect(find.textContaining('Returned by'), findsNothing);
    });

    testWidgets('a rejection strikes through what will never happen', (
      tester,
    ) async {
      await pump(tester, SapState.rejected);

      expect(find.text('Rejected — final'), findsOneWidget);

      TextStyle styleOf(String name) =>
          tester.widget<Text>(find.text(name)).style!;

      // Everything after the office is now impossible, so it is struck
      // through rather than left looking like work still ahead.
      for (final later in ['Signed', 'Approved', 'Completed']) {
        expect(
          styleOf(later).decoration,
          TextDecoration.lineThrough,
          reason: '$later still reads as something that will happen',
        );
      }
      // What already happened is still history, not struck out.
      expect(styleOf('Draft').decoration, isNot(TextDecoration.lineThrough));
    });

    testWidgets('a return leaves the stops ahead as real work', (tester) async {
      // The difference from a rejection: this proposal can still be
      // sent again, so nothing ahead of it is struck out.
      await pump(tester, SapState.revisionRequested);

      for (final later in ['The SDS Office', 'Approved', 'Completed']) {
        expect(
          tester.widget<Text>(find.text(later)).style!.decoration,
          isNot(TextDecoration.lineThrough),
          reason: '$later was struck out on a proposal that can be resent',
        );
      }
    });

    testWidgets('a screen reader hears the position, not the picture', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, SapState.approved);

      expect(find.bySemanticsLabel(RegExp(r'step 5 of 6')), findsOneWidget);
      handle.dispose();
    });
  });
}
