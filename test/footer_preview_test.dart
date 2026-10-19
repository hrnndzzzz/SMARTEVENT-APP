@Tags(['preview'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/widgets/page_indicator.dart';

/// Renders the footer in both themes, at each of its three positions.
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

  testWidgets('footer', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 300));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PageIndicator(
                current: 1,
                onGo: (_) {},
                labels: const ['Menu', 'Dashboard', 'Events'],
              ),
              PageIndicator(
                current: 0,
                onGo: (_) {},
                labels: const ['Menu', 'Dashboard', 'Events'],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('sap-preview/footer.png'),
    );
  });
}
