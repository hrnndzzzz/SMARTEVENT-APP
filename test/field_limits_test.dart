import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_part3_screen.dart';
import 'package:smartevent/screens/sap/sap_part4_screen.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

/// The server enforces a length on nearly every SAP text field and the
/// app enforced none of them, so an over-long answer was accepted,
/// saved, and refused as a 422 naming a field the writer cannot see.
///
/// These are the limits in Part 3. Part 1's three long answers are
/// capped by PR #16; the rest of Part 1 is still open.
void main() {
  testWidgets('Part 3 stops where the server stops', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SapPart3Screen(form: SapForm(eventId: 'e1')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // The label renders uppercased alongside the field rather than
    // inside it, so the field is found by its own label property.
    final fields = tester.widgetList<BrutTextField>(
      find.byType(BrutTextField),
    );
    final excuse = fields.firstWhere(
      (f) => f.label == 'Excuse letter arrangement',
    );

    expect(
      excuse.maxLength,
      400,
      reason: 'excuse_arrangement is max_length=400 on the server',
    );
  });

  testWidgets('Part 4 stops where the server stops', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2600);
    addTearDown(tester.view.reset);

    // Answers that open every text box Part 4 has.
    final form = SapForm(eventId: 'e1')
      ..setClearance(
        const SapClearance(
          parentsConsent: SapClearanceAnswer.notApplicable,
          attachments: 'Program and budget',
          classInterruption: SapClearanceAnswer.yes,
          medicalExam: SapClearanceAnswer.notApplicable,
          reportOfCompliance: SapClearanceAnswer.notApplicable,
          studentPersonnelRatio: '145:3',
        ),
      );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SapPart4Screen(form: form),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final fields = tester.widgetList<BrutTextField>(
      find.byType(BrutTextField),
    );
    expect(fields, hasLength(6));
    for (final field in fields) {
      expect(field.maxLength, 5000, reason: field.label);
    }
  });
}
