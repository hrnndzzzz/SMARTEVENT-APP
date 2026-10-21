@Tags(['preview'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartevent/state/app_settings.dart';
import 'package:smartevent/theme/app_theme.dart';
import 'package:smartevent/theme/brut.dart';

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

  testWidgets('spinner', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 160));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettings(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  BrutSpinner(size: 48),
                  BrutSpinner(),
                  BrutSpinner(size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // A known phase, so the arcs are where the eye expects them.
    await tester.pump(const Duration(milliseconds: 90));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('sap-preview/spinner.png'),
    );
  });
}
