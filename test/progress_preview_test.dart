@Tags(['preview'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/widgets/event_progress_bar.dart';

void main() {
  setUpAll(() async {
    for (final (family, files) in const [
      ('Lexend', ['fonts/Lexend-Regular.ttf', 'fonts/Lexend-Medium.ttf']),
      (
        'IBMPlexMono',
        ['fonts/IBMPlexMono-Regular.ttf', 'fonts/IBMPlexMono-Medium.ttf'],
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

  testWidgets('stages', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 600));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final (title, stage) in const [
                  ('Programming Bootcamp for Freshmen', EventStage.drafting),
                  ('Hackathon 2026: Code for Campus', EventStage.withSds),
                  ('Industry Immersion Talk', EventStage.rejected),
                  ('CITE Week: Opening Ceremony', EventStage.approved),
                ]) ...[
                  EventProgressBar(title: title, stage: stage, onTap: () {}),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('sap-preview/stages.png'),
    );
  });
}
