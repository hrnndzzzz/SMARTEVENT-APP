import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Writes the downloaded update into the cache folder that
/// `android/app/src/main/res/xml/update_paths.xml` shares with the
/// installer, and returns its path. Each download replaces the last one.
Future<String> saveApk(Stream<List<int>> bytes) async {
  final folder = Directory(
    p.join((await getTemporaryDirectory()).path, 'update'),
  );
  await folder.create(recursive: true);
  final file = File(p.join(folder.path, 'SMARTEVENT.apk'));
  final sink = file.openWrite();
  try {
    await sink.addStream(bytes);
  } finally {
    await sink.close();
  }
  return file.path;
}
