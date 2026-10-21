@Tags(['preview'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_form_screen.dart';
import 'package:smartevent/screens/sap/sap_part1_screen.dart';
import 'package:smartevent/screens/sap/sap_part2_screen.dart';
import 'package:smartevent/screens/sap/sap_part3_screen.dart';
import 'package:smartevent/screens/sap/sap_part5_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// Renders the form screens to PNGs so they can be looked at.
///
/// Assertions say a widget exists; they do not say it is legible, that
/// nothing overflows, or that the page reads like the paper it mirrors.
/// Run with `flutter test --tags preview test/sap_preview_test.dart`.
Future<void> _shoot(WidgetTester tester, String name, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light(), home: screen),
  );
  await tester.pumpAndSettle();

  // Written by `--update-goldens`; these are for looking at, not for
  // failing a build on a one-pixel shift.
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('sap-preview/$name.png'),
  );
}

void main() {
  setUpAll(() async {
    // The app's own faces, not Flutter's bundled Roboto. Without these
    // every glyph renders as an Ahem box and the preview shows layout
    // but no words, which is exactly the kind of screenshot that looks
    // fine and proves nothing.
    for (final (family, files) in const [
      ('Lexend', ['fonts/Lexend-Regular.ttf', 'fonts/Lexend-Medium.ttf']),
      (
        'IBMPlexMono',
        ['fonts/IBMPlexMono-Regular.ttf', 'fonts/IBMPlexMono-Medium.ttf'],
      ),
      (
        'MaterialIcons',
        [
          '/Users/Mizer/development/flutter/bin/cache/artifacts/'
              'material_fonts/MaterialIcons-Regular.otf',
        ],
      ),
    ]) {
      final loader = FontLoader(family);
      for (final path in files) {
        loader.addFont(
          Future.value(File(path).readAsBytesSync().buffer.asByteData()),
        );
      }
      await loader.load();
    }
  });

  SapForm filled() {
    final form = SapForm(eventId: 'e1');
    form.updateDetails(
      (d) => d.copyWith(
        title: 'HACK THE FUTURE: Cybersecurity and Ethical Hacking',
        organizationName: 'Association of Computer Engineering Students',
        course: 'BS Computer Engineering',
        // Dated so the thirty-day notice is satisfied and the render does
        // not move with the calendar: with no proposal date the rule
        // measures from today, and the golden would change daily.
        proposalDate: DateTime(2026, 9, 20),
        activityDate: DateTime(2026, 10, 28),
        startTime: const SapTime(8, 0),
        endTime: const SapTime(11, 0),
        modality: SapModality.online,
        setting: SapSetting.online,
        venue: 'Zoom Platform',
        personsInCharge: 'Engr. Aileen M. Habaradas, Engr. Glazen M. Perez',
        attire: 'Any decent attire',
        expectedStudents: 145,
        totalBudget: '2500.00',
        fundingSource: 'Organizational funds',
        coreValues: SapCoreValue.values,
        egas: const [1, 2, 3, 4],
      ),
    );
    form.setProgramFlow(const [
      SapProgramFlowItem(
        start: SapTime(8, 0),
        end: SapTime(8, 5),
        activity: 'Opening prayer',
      ),
      SapProgramFlowItem(
        start: SapTime(8, 25),
        end: SapTime(9, 40),
        activity: 'Main talk',
      ),
    ]);
    form.setBudgetItems(const [
      SapBudgetItem(particulars: 'Guest speaker', amount: '2000.00'),
      SapBudgetItem(particulars: 'Certificate and token', amount: '300.00'),
      SapBudgetItem(particulars: 'Seminar materials', amount: '200.00'),
    ]);
    return form;
  }

  testWidgets('preview', (tester) async {
    await _shoot(tester, 'hub', SapFormScreen(form: filled()));
    await _shoot(tester, 'part5', SapPart5Screen(form: filled()));

    // As the flow renders them: each part is a step, so each carries
    // the three-step bar rather than a plain header.
    await _shoot(
      tester,
      'part1',
      SapPart1Screen(form: filled(), step: 0, onContinue: (_) async {}),
    );
    await _shoot(
      tester,
      'part2',
      SapPart2Screen(form: filled(), step: 1, onContinue: (_) async {}),
    );
    await _shoot(
      tester,
      'part3',
      SapPart3Screen(form: filled(), step: 2, onContinue: (_) async {}),
    );
  });
}
