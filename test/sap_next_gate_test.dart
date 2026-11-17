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
    expect(
      find.textContaining('Fill these in before going on'),
      findsOneWidget,
    );
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

  testWidgets('a field filled by typing is a field that is filled', (
    tester,
  ) async {
    // The one the other tests here could not catch, because they all
    // fill the form through `updateDetails` and a proposer fills it
    // through the keyboard. Part 1's text fields are deliberately
    // uncontrolled — they fold into the model in `_collect` and
    // nowhere else, so that a keystroke does not rebuild the page —
    // which leaves the model a step behind what is on screen. The gate
    // read that model, so a title typed and a Next pressed was refused
    // for a missing title that was sitting right there.
    //
    // Everything on the step except the title, so the title is the one
    // thing the gate can be waiting for. It cannot be cleared after
    // the fact: `copyWith(title: null)` means "leave it", so a test
    // that filled it and then nulled it would be asserting nothing.
    final form = SapForm(eventId: 'e1');
    form.updateDetails(
      (d) => d.copyWith(
        organizationName: 'CITE Student Council',
        departmentType: 'College',
        department: 'CITE',
        schoolYear: '2025-2026',
        proposalDate: DateTime(2026, 11, 16),
      ),
    );
    await open(tester, form);
    expect(ProposalSteps.missingOn(form, ProposalSteps.activity), [
      'Activity title',
    ], reason: 'the title must be the only thing left for this to test');

    // By the widget's own label, not by its rendered text: MonoLabel
    // uppercases what it prints, so the screen says ACTIVITY TITLE.
    final titleField = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is BrutTextField && w.label == 'Activity title',
      ),
      matching: find.byType(EditableText),
    );
    expect(titleField, findsOneWidget);
    await tester.enterText(titleField, 'Foundation Week Booth');
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Next:'));
    await tester.pumpAndSettle();

    expect(
      find.text('When and where'),
      findsOneWidget,
      reason: 'the typed title never reached the model the gate reads',
    );
    expect(find.textContaining('Still needed here'), findsNothing);
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
