import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Loads the app's real fonts for every test in this directory.
///
/// Without it `flutter_test` substitutes a fixed-width test font, so
/// every glyph is the same box whatever the family — which means a
/// layout sweep measures nothing real, and a change from Lexend to a
/// mono that runs 15% wider looks free. Found when the sweep reported
/// the same 25px overflow before and after the family changed.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final family in const {
    'Lexend': ['fonts/Lexend-Regular.ttf', 'fonts/Lexend-Medium.ttf'],
    'IBMPlexMono': [
      'fonts/IBMPlexMono-Regular.ttf',
      'fonts/IBMPlexMono-Medium.ttf',
    ],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final path in family.value) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(
        Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
      );
    }
    await loader.load();
  }
  await testMain();
}
