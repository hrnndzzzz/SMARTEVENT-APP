import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/screens/sap/proposal_steps.dart';
import 'package:smartevent/screens/sap/sap_steps_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// Next refuses a step that still has gaps in it.
///
/// The complaint behind this was about forgetting, not about rules:
/// everything required sits on Part 1, and nothing said so until the
/// proposer reached the last step and found Send for review would not
/// go. Five steps is a long way to carry a blank venue.
///
/// Two things it must *not* do, and both are tested here. It must not
/// go grey — a dead button cannot say why, which is the fault this
/// whole batch started with. And it must not trap anybody: back and
/// save-as-draft stay open, or the reminder becomes a cage and a
/// half-written proposal can never be parked.
void main() {
  Widget host(SapForm form) => MaterialApp(
    theme: AppTheme.light(),
    home: SapStepsScreen(
      form: form,
      onCreateEvent: (_) async {
        await form.bindEvent('e1');
        return true;
      },
      onSubmit: (_) async {},
    ),
  );

  Future<void> open(WidgetTester tester, SapForm form) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    await tester.pumpWidget(host(form));
    await tester.pumpAndSettle();
  }

  /// Everything the first step asks for, so a test about the second
  /// step is not really a test about the first.
  void fillActivity(SapForm form) => form.updateDetails(
    (d) => d.copyWith(
      title: 'Foundation Week Booth',
      organizationName: 'CITE Student Council',
      departmentType: 'College',
      department: 'CITE',
      schoolYear: '2025-2026',
      proposalDate: DateTime(2026, 11, 16),
    ),
  );

  testWidgets('a blank step will not go on, and says what it wants', (
    tester,
  ) async {
    await open(tester, SapForm(eventId: 'e1'));

    await tester.tap(find.textContaining('Next:'));
    await tester.pumpAndSettle();

    // Still on the activity step.
    expect(find.text('Activity Details'), findsOneWidget);
    expect(find.textContaining('Fill these in before going on'), findsOneWidget);
    expect(find.textContaining('Activity title'), findsWidgets);
  });

  testWidgets('it asks only for what is on this step', (tester) async {
    await open(tester, SapForm(eventId: 'e1'));

    await tester.tap(find.textContaining('Next:'));
    await tester.pumpAndSettle();

    final banner = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((t) => t.startsWith('Fill these in before going on'));
    // The venue is on the step after this one. Naming it here would be
    // refusing a page for work the proposer has not been shown yet.
    expect(banner, contains('Activity title'));
    expect(banner, isNot(contains('Venue')));
  });

  testWidgets('a filled step goes on', (tester) async {
    final form = SapForm(eventId: 'e1');
    fillActivity(form);
    await open(tester, form);

    expect(
      ProposalSteps.missingOn(form, ProposalSteps.activity),
      isEmpty,
      reason: 'the fixture no longer fills the whole first step',
    );

    await tester.tap(find.textContaining('Next:'));
    await tester.pumpAndSettle();

    expect(find.text('When and where'), findsOneWidget);
  });

  testWidgets('the button never goes grey', (tester) async {
    await open(tester, SapForm(eventId: 'e1'));

    // The regression that started all of this: a control that refuses
    // by being dead has no way to say why it refused.
    final button = tester.widget<BrutButton>(
      find
          .ancestor(
            of: find.textContaining('Next:'),
            matching: find.byType(BrutButton),
          )
          .first,
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('and the way back out is still open', (tester) async {
    await open(tester, SapForm(eventId: 'e1'));

    await tester.tap(find.textContaining('Next:'));
    await tester.pumpAndSettle();

    // Refused, but not trapped: the header's back button still offers
    // to keep the work as a draft.
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    expect(find.text('Leave this proposal?'), findsOneWidget);
    expect(find.text('Save as draft'), findsOneWidget);
  });
}
