import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'private_files.dart';

class OfflineSession {
  OfflineSession(this.backend, this.profile);
  final String backend;
  final Map<String, dynamic> profile;
  String get scope => jsonEncode([
    backend,
    profile['id'],
    profile['role'],
    profile['department_id'],
    profile['organization_id'],
  ]);
}

class Snapshot {
  const Snapshot(this.data, this.savedAt);
  final dynamic data;
  final DateTime savedAt;
}

class SavedFile {
  const SavedFile(this.bytes, this.contentType, this.filename, this.savedAt);
  final List<int> bytes;
  final String contentType;
  final String filename;
  final DateTime savedAt;
}

/// One verified account's downloaded data. Replacing identity clears its namespace.
class OfflineStore {
  OfflineStore._(this._db, this._files);
  final Database _db;
  final PrivateFiles _files;
  OfflineSession? session;
  int generation = 0;
  String? error;
  Future<void> _fileWork = Future.value();

  static Future<OfflineStore> open({
    String? directory,
    DatabaseFactory? factory,
  }) async {
    final root = directory ?? await offlineDirectory();
    final db = await (factory ?? databaseFactory).openDatabase(
      p.join(root, 'snapshots.sqlite'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE snapshots (key TEXT PRIMARY KEY, body TEXT NOT NULL, saved_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE files (key TEXT PRIMARY KEY, name TEXT NOT NULL, mime TEXT NOT NULL, filename TEXT NOT NULL, saved_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE file_owners (owner TEXT NOT NULL, key TEXT NOT NULL, PRIMARY KEY(owner, key))',
          );
        },
      ),
    );
    final store = OfflineStore._(db, PrivateFiles(root));
    final saved = await store.metadata('session');
    if (saved is Map) {
      store.session = OfflineSession(
        saved['backend'] as String,
        Map<String, dynamic>.from(saved['profile'] as Map),
      );
    }
    return store;
  }

  static String key(String path, [Map<String, String>? query]) {
    if (query == null || query.isEmpty) return path;
    final names = query.keys.toList()..sort();
    return '$path?${names.map((n) => '${Uri.encodeQueryComponent(n)}=${Uri.encodeQueryComponent(query[n]!)}').join('&')}';
  }

  Future<dynamic> metadata(String key) async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }

  Future<void> setMetadata(String key, Object? value, {int? generation}) async {
    final expected = generation ?? this.generation;
    await _db.transaction((tx) async {
      if (expected != this.generation) return;
      await tx.insert('meta', {
        'key': key,
        'value': jsonEncode(value),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> activate(String backend, Map<String, dynamic> profile) async {
    final next = OfflineSession(backend, Map.of(profile));
    if (session?.scope != next.scope) await clear();
    session = next;
    await setMetadata('session', {'backend': backend, 'profile': profile});
  }

  Future<void> clear() async {
    generation++;
    session = null;
    await _fileWork;
    final oldFiles = await _db.query('files', columns: ['name']);
    await _db.transaction((tx) async {
      for (final table in ['meta', 'snapshots', 'files', 'file_owners']) {
        await tx.delete(table);
      }
    });
    for (final row in oldFiles) {
      try {
        await _files.delete(row['name'] as String);
      } catch (_) {
        /* No longer addressable. */
      }
    }
  }

  Future<void> put(String key, Object? data, {int? generation}) async {
    final expected = generation ?? this.generation;
    final encoded = jsonEncode(data);
    await _db.transaction((tx) async {
      if (session == null || expected != this.generation) return;
      await tx.insert('snapshots', {
        'key': key,
        'body': encoded,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<Snapshot?> read(String key) async {
    if (session == null) return null;
    final epoch = generation;
    final rows = await _db.query(
      'snapshots',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty || epoch != generation) return null;
    try {
      return Snapshot(
        jsonDecode(rows.first['body'] as String),
        DateTime.parse(rows.first['saved_at'] as String),
      );
    } on FormatException {
      await _db.delete('snapshots', where: 'key = ?', whereArgs: [key]);
      return null;
    }
  }

  Future<List<String>> keys() async => [
    for (final row in await _db.query('snapshots', columns: ['key']))
      row['key'] as String,
  ];

  /// List filters are projections of a complete download, not of a viewed page.
  Future<Snapshot?> readRequest(String path, Map<String, String>? query) async {
    final q = query ?? const <String, String>{};
    const supported = {
      'school_year',
      'missing_school_year',
      'is_draft',
      'missing_event',
      'flagged_only',
      'review_status',
      'unread_only',
      'event_id',
      'offset',
      'limit',
    };
    if (q.keys.any((name) => !supported.contains(name)))
      return read(key(path, query));
    const filterable = {
      '/events',
      '/inventory',
      '/incomes',
      '/receipts',
      '/notifications',
    };
    if (filterable.contains(path) && q.isNotEmpty) {
      final all = await read(path);
      if (all?.data is List) {
        final rows = <dynamic>[];
        for (final row in all!.data as List) {
          if (row is! Map) continue;
          if (q['school_year'] != null &&
              row['school_year'] != q['school_year'])
            continue;
          if (q['missing_school_year'] == 'true' && row['school_year'] != null)
            continue;
          if (q['is_draft'] != null &&
              row['is_draft'].toString() != q['is_draft'])
            continue;
          if (q['missing_event'] == 'true' && row['event_id'] != null) continue;
          if (q['flagged_only'] == 'true' && row['is_flagged'] != true)
            continue;
          if (q['review_status'] != null &&
              row['review_status'] != q['review_status'])
            continue;
          if (q['unread_only'] == 'true' && row['read_at'] != null) continue;
          if (q['event_id'] != null && row['event_id'] != q['event_id']) {
            if (path != '/inventory') continue;
            final movements = await read(
              '/inventory/${row['id']}/transactions',
            );
            // An incomplete ledger cannot prove an item is absent from a filter.
            if (movements == null) return read(key(path, query));
            if (!(movements.data as List).any(
              (m) => m['event_id'] == q['event_id'],
            ))
              continue;
          }
          rows.add(row);
        }
        final offset = int.tryParse(q['offset'] ?? '') ?? 0;
        final limit = int.tryParse(q['limit'] ?? '') ?? rows.length;
        return Snapshot(rows.skip(offset).take(limit).toList(), all.savedAt);
      }
    }
    return read(key(path, query));
  }

  Future<void> putFile(
    String key,
    List<int> bytes,
    String mime,
    String filename, {
    int? generation,
    String? owner,
  }) async {
    final expected = generation ?? this.generation;
    final operation = _fileWork.then(
      (_) => _putFile(
        key,
        bytes,
        mime,
        filename,
        generation: expected,
        owner: owner,
      ),
    );
    _fileWork = operation.catchError((Object _) {});
    await operation;
  }

  Future<void> _putFile(
    String key,
    List<int> bytes,
    String mime,
    String filename, {
    required int generation,
    String? owner,
  }) async {
    final expected = generation;
    if (session == null || expected != this.generation) return;
    final name = sha256
        .convert(utf8.encode('${session!.scope}|$key|${sha256.convert(bytes)}'))
        .toString();
    await _files.write(name, bytes);
    if (expected != this.generation) {
      await _files.delete(name);
      return;
    }
    String? oldName;
    var inserted = false;
    try {
      await _db.transaction((tx) async {
        if (expected != this.generation || session == null) return;
        final old = await tx.query(
          'files',
          columns: ['name'],
          where: 'key = ?',
          whereArgs: [key],
        );
        oldName = old.isEmpty ? null : old.first['name'] as String;
        await tx.insert('files', {
          'key': key,
          'name': name,
          'mime': mime,
          'filename': filename,
          'saved_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (owner != null) {
          await tx.insert('file_owners', {
            'owner': owner,
            'key': key,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        inserted = true;
      });
    } finally {
      if (!inserted) await _files.delete(name);
    }
    if (oldName != null && oldName != name) await _files.delete(oldName!);
  }

  Future<SavedFile?> readFile(String key) async {
    if (session == null) return null;
    final epoch = generation;
    final rows = await _db.query('files', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final bytes = await _files.read(row['name'] as String);
    if (bytes == null || epoch != generation) return null;
    return SavedFile(
      bytes,
      row['mime'] as String,
      row['filename'] as String,
      DateTime.parse(row['saved_at'] as String),
    );
  }

  Future<void> remove(String path) async {
    final expected = generation;
    final removedNames = <String>{};
    await _db.transaction((tx) async {
      if (expected != generation) return;
      final prefixes = [
        path,
        if (path.startsWith('/events/'))
          path.replaceFirst('/events/', '/reports/event/'),
      ];
      for (final prefix in prefixes) {
        final owned = await tx.query(
          'file_owners',
          where: 'owner = ? OR owner LIKE ?',
          whereArgs: [prefix, '$prefix/%'],
        );
        final direct = await tx.query(
          'files',
          where: 'key = ? OR key LIKE ? OR key LIKE ?',
          whereArgs: [prefix, '$prefix/%', '$prefix?%'],
        );
        await tx.delete(
          'snapshots',
          where: 'key = ? OR key LIKE ? OR key LIKE ?',
          whereArgs: [prefix, '$prefix/%', '$prefix?%'],
        );
        await tx.delete(
          'file_owners',
          where: 'owner = ? OR owner LIKE ?',
          whereArgs: [prefix, '$prefix/%'],
        );
        final candidates = {
          ...owned.map((r) => r['key']),
          ...direct.map((r) => r['key']),
        };
        for (final key in candidates) {
          if ((await tx.query(
            'file_owners',
            where: 'key = ?',
            whereArgs: [key],
          )).isNotEmpty)
            continue;
          final files = await tx.query(
            'files',
            where: 'key = ?',
            whereArgs: [key],
          );
          removedNames.addAll(files.map((r) => r['name'] as String));
          await tx.delete('files', where: 'key = ?', whereArgs: [key]);
        }
      }
      final parts = path.split('/');
      if (parts.length == 3) {
        final collection = '/${parts[1]}';
        final lists = await tx.query(
          'snapshots',
          where: 'key = ? OR key LIKE ?',
          whereArgs: [collection, '$collection?%'],
        );
        for (final row in lists) {
          final data = jsonDecode(row['body'] as String);
          if (data is! List) continue;
          data.removeWhere(
            (item) => item is Map && item['id'].toString() == parts[2],
          );
          await tx.update(
            'snapshots',
            {'body': jsonEncode(data)},
            where: 'key = ?',
            whereArgs: [row['key']],
          );
        }
      }
    });
    for (final name in removedNames) {
      await _files.delete(name);
    }
  }

  Future<void> removeFile(String key) async {
    await _fileWork;
    final rows = await _db.query('files', where: 'key = ?', whereArgs: [key]);
    await _db.transaction((tx) async {
      await tx.delete('file_owners', where: 'key = ?', whereArgs: [key]);
      await tx.delete('files', where: 'key = ?', whereArgs: [key]);
    });
    for (final row in rows) {
      await _files.delete(row['name'] as String);
    }
  }

  Future<void> prune(
    String collection,
    List<dynamic> previous,
    List<dynamic> current,
  ) async {
    final ids = {for (final row in current.whereType<Map>()) row['id']};
    for (final row in previous.whereType<Map>()) {
      if (!ids.contains(row['id'])) await remove('$collection/${row['id']}');
    }
  }

  Future<void> close() => _db.close();
}
