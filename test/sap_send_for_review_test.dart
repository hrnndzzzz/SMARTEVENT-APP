import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/screens/sap/proposal_steps.dart';
import 'package:smartevent/screens/sap/sap_part3_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// "Send for review" used to go dead, and a dead button is the one
/// control that cannot tell you why.
///
/// Everything the proposal is waiting on lives on steps the proposer has
/// already left. The list of what was missing was drawn at the top of
/// the last step and the button is at the bottom of it, so by the time
/// you reached the button the explanation was a screen and a half above
/// your thumb — which is exactly how it was reported: "cant send for
/// review", with no more to say about it, because there was nothing on
/// screen to say.
void main() {
  Widget host(SapForm form, {Future<void> Function(int)? onJumpTo}) => MaterialApp(
    theme: AppTheme.light(),
    home: SapPart3Screen(
      form: form,
      step: ProposalSteps.breakdown,
      onJumpTo: onJumpTo,
    ),
  );

  group('every required field knows which step it is on', () {
    test('an empty form maps all of them', () {
      // The labels come from the form itself rather than being typed
      // here, so a field renamed on one side cannot quietly stop being
      // routed on the other.
      final missing = SapForm(eventId: 'e1').missingForSubmit;
      expect(missing, isNotEmpty);
      for (final label in missing) {
        final step = ProposalSteps.stepForMissing(label);
        expect(
          step,
          inInclusiveRange(0, ProposalSteps.count - 1),
          reason: '$label is routed off the end of the bar',
        );
      }
    });

    test('and they go where the field is actually drawn', () {
      expect(
        ProposalSteps.stepForMissing('Activity title'),
        ProposalSteps.activity,
      );
      expect(ProposalSteps.stepForMissing('Venue'), ProposalSteps.schedule);
      expect(ProposalSteps.stepForMissing('Start time'), ProposalSteps.schedule);
      // Part 1's third step carries the budget figure, while the lines
      // that have to add up to it are on the breakdown.
      expect(ProposalSteps.stepForMissing('Budget'), ProposalSteps.details);
      expect(
        ProposalSteps.stepForMissing('Emergency plan'),
        ProposalSteps.details,
      );
      expect(
        ProposalSteps.stepForMissing(
          'Budget breakdown that adds up to the budget',
        ),
        ProposalSteps.breakdown,
      );
    });
  });

  group('pressing it on an unfinished proposal', () {
    testWidgets('says what is missing instead of doing nothing', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      await tester.pumpWidget(host(SapForm(eventId: 'e1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send for review'));
      await tester.pumpAndSettle();

      expect(find.text('Not ready to send'), findsOneWidget);
      // Grouped by step, so the answer is "which screen do I go to",
      // not a flat list of twenty-eight field names.
      expect(find.text(ProposalSteps.labels[ProposalSteps.activity]),
          findsWidgets);
      expect(find.textContaining('Activity title'), findsWidgets);
    });

    testWidgets('and a tap on a step goes back to it', (tester) async {
      int? jumped;
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      await tester.pumpWidget(
        host(SapForm(eventId: 'e1'), onJumpTo: (i) async => jumped = i),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send for review'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(ProposalSteps.labels[ProposalSteps.activity]).last,
      );
      await tester.pumpAndSettle();

      expect(jumped, ProposalSteps.activity);
    });

    testWidgets('the button is never dead while the form is editable', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      await tester.pumpWidget(host(SapForm(eventId: 'e1')));
      await tester.pumpAndSettle();

      // The regression this whole file exists for: pressing it had no
      // effect at all, so there was nothing to report but "cant send".
      await tester.tap(find.text('Send for review'));
      await tester.pumpAndSettle();
      expect(
        find.text('Not ready to send'),
        findsOneWidget,
        reason: 'the press did nothing, which is where we came in',
      );
    });
  });
}
