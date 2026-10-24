import 'dart:typed_data';

Future<String> offlineDirectory() => throw UnsupportedError('Mobile only');

class PrivateFiles {
  PrivateFiles(String directory);
  Future<void> write(String name, List<int> bytes) =>
      throw UnsupportedError('Mobile only');
  Future<Uint8List?> read(String name) => throw UnsupportedError('Mobile only');
  Future<void> delete(String name) => throw UnsupportedError('Mobile only');
}
