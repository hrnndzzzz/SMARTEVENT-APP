import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/screens/sap/proposal_steps.dart';
import 'package:smartevent/screens/sap/sap_steps_screen.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// Filling the proposal in, as five steps on one screen.
///
/// This replaces sap_steps_swipe_test.dart. Part 1 carried about
/// twenty-five fields on one scroll and the people who tried it said
/// there was too much happening, so it is three steps now — and with
/// five pages rather than three, swiping between them was dropped in
/// favour of Next and the step bar.
///
/// Swiping was not an accident: it was there so somebody on the
/// breakdown could go back and check the activity without backing out
/// of the flow. The step bar has to carry that, which is what the jump
/// tests below are for.
void main() {
  Widget host(
    SapForm form, {
    VoidCallback? onCreate,
    VoidCallback? onSubmit,
    bool created = true,
  }) => MaterialApp(
    theme: AppTheme.light(),
    home: SapStepsScreen(
      form: form,
      onCreateEvent: (_) async {
        onCreate?.call();
        if (created) await form.bindEvent('e1');
        return created;
      },
      onSubmit: (_) async => onSubmit?.call(),
    ),
  );

  /// The three fields the last step of Part 1 refuses to pass without.
  /// Filled up front so a navigation test is testing navigation.
  void fillRequired(SapForm form) => form.updateDetails(
    (d) => d.copyWith(
      setting: SapSetting.onCampus,
      departmentType: 'College',
      department: 'CITE',
    ),
  );

  Future<void> open(WidgetTester tester, SapForm form, {bool created = true,
      VoidCallback? onCreate}) async {
    fillRequired(form);
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(
      host(form, created: created, onCreate: onCreate),
    );
    await tester.pumpAndSettle();
  }

  /// Advances one step by its Next button, whatever that step calls it.
  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.textContaining('Next:'));
    await tester.pumpAndSettle();
  }

  Future<void> swipe(WidgetTester tester, double dx) => tester.flingFrom(
    tester.getTopLeft(find.byType(PageView)) + const Offset(210, 40),
    Offset(dx, 0),
    1200,
  );

  group('the five steps', () {
    testWidgets('it opens on the activity', (tester) async {
      await open(tester, SapForm(eventId: 'e1'));

      expect(find.text('Activity Details'), findsOneWidget);
    });

    testWidgets('Part 1 is three steps, each naming what it asks for', (
      tester,
    ) async {
      await open(tester, SapForm(eventId: 'e1'));
      expect(find.text('Activity Details'), findsOneWidget);

      await next(tester);
      expect(find.text('When and where'), findsOneWidget);

      await next(tester);
      expect(find.text('About the activity'), findsOneWidget);
    });

    testWidgets('and the fourth step is Part 2', (tester) async {
      await open(tester, SapForm(eventId: 'e1'));
      for (var i = 0; i < 3; i++) {
        await next(tester);
      }

      expect(find.text('School Support'), findsOneWidget);
    });

    testWidgets('all five exist at once, not pushed one at a time', (
      tester,
    ) async {
      await open(tester, SapForm(eventId: 'e1'));

      expect(find.byType(PageView), findsOneWidget);
      expect(ProposalSteps.labels, hasLength(5));
    });
  });

  group('swiping is off', () {
    testWidgets('a swipe does not leave the activity', (tester) async {
      await open(tester, SapForm(eventId: 'e1'));

      await swipe(tester, -400);
      await tester.pumpAndSettle();

      expect(
        find.text('Activity Details'),
        findsOneWidget,
        reason: 'a swipe past Part 1 skipped the event record being made',
      );
    });
  });

  group('the step bar goes back', () {
    testWidgets('a passed step can be jumped to', (tester) async {
      await open(tester, SapForm(eventId: 'e1'));
      await next(tester);
      await next(tester);
      expect(find.text('About the activity'), findsOneWidget);

      // The bar itself is the button, not its caption: it carries the
      // step's name as a semantics label and the caption is uppercased.
      await tester.tap(
        find.bySemanticsLabel(ProposalSteps.labels.first).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Activity Details'),
        findsOneWidget,
        reason: 'this is what swiping used to be for',
      );
    });

    testWidgets('a step not yet reached is not a button', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, SapForm(eventId: 'e1'));

      // A step with no jump is drawn but not interactive, and a
      // Semantics node carrying only a label merges into its parent —
      // so the bar for a step still ahead is not reachable as a
      // control at all. Jumping forward would skip the event record.
      expect(find.bySemanticsLabel(ProposalSteps.labels.last), findsNothing);
      expect(find.bySemanticsLabel(ProposalSteps.labels[1]), findsNothing);

      handle.dispose();
    });

    testWidgets('and the one behind becomes a button once passed', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, SapForm(eventId: 'e1'));
      expect(find.bySemanticsLabel(ProposalSteps.labels.first), findsNothing);

      await next(tester);

      expect(
        find.bySemanticsLabel(ProposalSteps.labels.first),
        findsOneWidget,
        reason: 'the step just left is now a way back',
      );
      handle.dispose();
    });
  });

  group('the event record', () {
    testWidgets('is made on the way out of Part 1, not before', (
      tester,
    ) async {
      var made = 0;
      await open(tester, SapForm(eventId: null), onCreate: () => made++);

      await next(tester);
      expect(made, 0, reason: 'the date is not in hand yet');
      await next(tester);
      expect(made, 0, reason: 'still inside Part 1');

      await next(tester);
      expect(made, 1, reason: 'leaving Part 1 is what makes it');
    });

    testWidgets('one that cannot be made keeps you on the last step', (
      tester,
    ) async {
      await open(tester, SapForm(eventId: null), created: false);
      await next(tester);
      await next(tester);

      await next(tester);

      expect(find.text('About the activity'), findsOneWidget);
      expect(find.text('School Support'), findsNothing);
    });
  });
}
