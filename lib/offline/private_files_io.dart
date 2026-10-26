import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> offlineDirectory() async =>
    p.join((await getApplicationSupportDirectory()).path, 'offline');

class PrivateFiles {
  PrivateFiles(this.directory);
  final String directory;
  File _file(String name) {
    if (!RegExp(r'^[a-f0-9]+$').hasMatch(name)) {
      throw ArgumentError('Invalid private file name');
    }
    return File(p.join(directory, 'files', name));
  }

  Future<void> write(String name, List<int> bytes) async {
    final target = _file(name);
    await target.parent.create(recursive: true);
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (await target.exists()) {
        await temporary.delete();
      } else {
        await temporary.rename(target.path);
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Uint8List?> read(String name) async {
    final file = _file(name);
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> delete(String name) async {
    final file = _file(name);
    if (await file.exists()) await file.delete();
  }
}
