@Tags(['preview'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/screens/sap/sap_proposer_flow_screen.dart';
import 'package:smartevent/state/sap_form.dart';
import 'package:smartevent/theme/app_theme.dart';

void main() {
  setUpAll(() async {
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

  testWidgets('flow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 820));
    final form = SapForm(eventId: 'e1');
    form.updateDetails(
      (d) => d.copyWith(title: 'Hack the Future', organizationName: 'ACPES'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SapProposerFlowScreen(form: form),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('sap-preview/proposer-flow.png'),
    );
  });

  testWidgets('bar', (tester) async {
    // Five labels at phone width is the thing worth looking at: they
    // either fit or they do not.
    await tester.binding.setSurfaceSize(const Size(390, 420));
    final form = SapForm(eventId: 'e1');
    form.updateDetails((d) => d.copyWith(title: 'Hack the Future'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SapProposerFlowScreen(form: form),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('sap-preview/proposal-bar.png'),
    );
  });

  testWidgets('waiting', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 620));
    final form = SapForm(eventId: 'e1')
      ..adoptForTest(state: SapState.pendingReview);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SapProposerFlowScreen(form: form),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('sap-preview/proposer-waiting.png'),
    );
  });
}
