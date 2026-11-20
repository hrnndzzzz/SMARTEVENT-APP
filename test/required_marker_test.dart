import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// A field that has to be filled says so before you press Next.
///
/// Asked for by a survey reviewer: "Include indicators that a part is
/// required, like 'Event name' marked with * or similar to further
/// decrease mistake chance." Before this the only way to find out was
/// to fill in everything else, press Next, and be refused.
void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light(), home: child);

  testWidgets('the marker is on, and only on, a required field', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 3400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(SapPart1Screen(form: SapForm(eventId: 'e1'))));
    await tester.pump(const Duration(milliseconds: 400));

    RequiredLabel labelFor(String text) => tester
        .widgetList<RequiredLabel>(find.byType(RequiredLabel))
        .firstWhere(
          (w) => w.text == text,
          orElse: () => throw StateError('no label "$text" on Part 1'),
        );

    // Named in SapForm's own `missing` list, so the marker and the
    // refusal cannot disagree about what has to be filled in.
    for (final name in [
      'Activity title',
      'Organization',
      'Venue',
      'Rationale',
      'Objectives',
      'Emergency plan',
      'Source of budget',
    ]) {
      expect(
        labelFor(name).required,
        isTrue,
        reason: '"$name" is refused when blank but was not marked',
      );
    }

    // And one the form is happy to leave empty, so the asterisk means
    // something rather than being decoration on every field.
    expect(
      labelFor('Attire').required,
      isFalse,
      reason: 'Attire is optional and was marked as required',
    );
  });

  testWidgets('a screen reader is told in words, not punctuation', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        const Scaffold(
          body: BrutTextField(label: 'Activity title', required: true),
        ),
      ),
    );
    await tester.pump();

    // "star" means nothing read aloud.
    expect(find.bySemanticsLabel('Activity title, required'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an optional field is left alone', (tester) async {
    await tester.pumpWidget(
      host(const Scaffold(body: BrutTextField(label: 'Attire'))),
    );
    await tester.pump();

    expect(find.text('ATTIRE'), findsOneWidget);
    expect(find.textContaining('*'), findsNothing);
  });
}
