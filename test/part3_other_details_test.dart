import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_part3_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

/// A filled form writes this part under ten headings. A single box
/// labelled "other details" is how it ends up empty.
void main() {
  testWidgets('every heading a real form uses is asked for', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2600));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SapPart3Screen(form: SapForm(eventId: 'e1')),
      ),
    );
    await tester.pumpAndSettle();

    for (final heading in const [
      'ATTENDANCE MONITORING',
      'FOCUS',
      'ATTIRE',
      'GUEST SPEAKER COORDINATION',
      'CLASS INTERRUPTION NOTICE',
      'EDUCATIONAL CONTINUITY',
      'CERTIFICATES OR CREDITS',
      'REGISTRATION PROCESS',
      'TARGET AUDIENCE',
      'DOCUMENTATION AND MEDIA COVERAGE',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: 'missing $heading');
    }
  });

  testWidgets('what was stored comes back under its own heading', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2600));
    final form = SapForm(eventId: 'e1');
    form.updateDetails(
      (d) => d.copyWith(
        additionalInformation:
            'Focus: Securing code from day one.\n\n'
            'Target audience: All BSIT students.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SapPart3Screen(form: form),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Securing code from day one.'), findsOneWidget);
    expect(find.text('All BSIT students.'), findsOneWidget);
  });
}
