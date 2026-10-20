@Tags(['preview'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartevent/screens/sap/sap_review_demo_screen.dart';
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

  testWidgets('review demo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 1900));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const SapReviewDemoScreen()),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('sap-preview/review-demo.png'),
    );
  });
}
