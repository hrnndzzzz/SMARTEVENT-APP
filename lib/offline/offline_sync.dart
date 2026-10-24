import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../state/user_role.dart';
import 'offline_store.dart';

/// Foreground preparation uses the same scoped GET routes as the screens.
class OfflineSync extends ChangeNotifier {
  OfflineSync(this.api);
  final ApiClient api;
  bool running = false;
  bool foreground = true;
  int completed = 0;
  int total = 0;
  int failed = 0;
  DateTime? lastCompleted;
  int _run = 0;
  bool _disposed = false;
  bool _rerun = false;
  final List<Future<void> Function()> _jobs = [];
  bool get ready => lastCompleted != null && failed == 0 && !running;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    _run++;
  }

  Future<void> refreshAfterMutation() async {
    final store = api.offlineStore;
    if (store == null || !api.hasOfflineSession || _disposed) return;
    try {
      await store.setMetadata(
        'sync_started_at',
        null,
        generation: store.generation,
      );
      cancel();
      await prepare();
    } catch (_) {
      failed++;
      _notify();
    }
  }

  Future<void> prepare() async {
    if (_disposed) return;
    if (running) {
      _rerun = true;
      return;
    }
    _rerun = false;
    try {
      await _prepare();
    } catch (_) {
      failed++;
      running = false;
      _notify();
    } finally {
      if (_rerun && foreground && api.canWriteRemote && !_disposed)
        await prepare();
    }
  }

  Future<void> _prepare() async {
    final store = api.offlineStore;
    if (running ||
        !foreground ||
        !api.canWriteRemote ||
        !api.hasOfflineSession ||
        store == null)
      return;
    final role = userRoleFromWire(store.session!.profile['role'] as String);
    if (role == null) return;
    final run = ++_run;
    final generation = store.generation;
    bool current() =>
        run == _run &&
        generation == store.generation &&
        foreground &&
        api.canWriteRemote;
    running = true;
    completed = 0;
    failed = 0;
    total = 0;
    _jobs.clear();
    store.error = null;
    final unfinished = await store.metadata('sync_started_at');
    final started = unfinished is String
        ? DateTime.parse(unfinished)
        : DateTime.now().toUtc();
    await store.setMetadata(
      'sync_started_at',
      started.toIso8601String(),
      generation: generation,
    );
    void add(Future<void> Function() job) {
      _jobs.add(job);
      total++;
    }

    Future<void> file(
      String reference,
      String owner, {
      String? linkPath,
    }) async {
      final saved = await store.readFile(linkPath ?? 'asset:$reference');
      if (saved != null && !saved.savedAt.isBefore(started)) return;
      await api.storedFile(
        reference,
        linkPath: linkPath,
        owner: owner,
        policy: ReadPolicy.networkOnly,
      );
    }

    void files(dynamic data, String owner) {
      if (data is Map) {
        for (final entry in data.entries) {
          if ([
                'receipt_url',
                'document_url',
                'image_url',
                'photo_url',
              ].contains(entry.key) &&
              entry.value is String &&
              (entry.value as String).isNotEmpty) {
            add(() => file(entry.value as String, owner));
          } else if (entry.value is Map || entry.value is List) {
            files(entry.value, owner);
          }
        }
      } else if (data is List) {
        for (final row in data) {
          files(
            row,
            row is Map && row['id'] != null ? '$owner/${row['id']}' : owner,
          );
        }
      }
    }

    void read(
      String path, {
      Map<String, String>? query,
      void Function(dynamic)? after,
    }) {
      add(() async {
        final previous = await store.read(OfflineStore.key(path, query));
        final data = previous != null && !previous.savedAt.isBefore(started)
            ? previous.data
            : await api.get(path, query: query, policy: ReadPolicy.networkOnly);
        if (!current()) return;
        files(data, path);
        after?.call(data);
      });
    }

    void pdf(String path, {Map<String, String>? query}) {
      add(() async {
        final saved = await store.readFile(OfflineStore.key(path, query));
        if (saved != null && !saved.savedAt.isBefore(started)) return;
        await api.download(
          path,
          query: query,
          expectedContentType: 'application/pdf',
          fallbackFilename: 'report.pdf',
          policy: ReadPolicy.networkOnly,
        );
      });
    }

    void collection(String path, void Function(Map) detail) {
      read(
        path,
        after: (data) {
          if (data is List) {
            for (final row in data.whereType<Map>()) {
              detail(row);
            }
          }
        },
      );
    }

    if (role.hasOperationalAccess) {
      collection('/events', (row) {
        final path = '/events/${row['id']}';
        for (final suffix in [
          '',
          '/approvals',
          '/logistics',
          '/routing',
          '/readiness',
          '/sap-proposal',
          '/sap-proposal/workflow',
        ]) {
          read('$path$suffix');
        }
        read(
          '$path/sap-proposal/attachments',
          after: (data) {
            final rows = data is List
                ? data
                : data is Map
                ? data['attachments']
                : null;
            if (rows is List) {
              for (final attachment in rows.whereType<Map>()) {
                add(
                  () => file(
                    '',
                    path,
                    linkPath:
                        '$path/sap-proposal/attachments/${attachment['id']}/download',
                  ),
                );
              }
            }
          },
        );
        pdf('$path/sap-proposal/pdf');
        read('/reports/event/${row['id']}');
        pdf('/reports/event/${row['id']}/export', query: {'format': 'pdf'});
      });
      collection('/categories', (row) {
        read('/reports/category/${row['id']}');
        read(
          '/recommendations/event-budget',
          query: {'category_id': '${row['id']}'},
        );
        pdf('/reports/category/${row['id']}/export', query: {'format': 'pdf'});
      });
      collection('/expenses', (row) {
        for (final suffix in ['', '/items', '/approvals']) {
          read('/expenses/${row['id']}$suffix');
        }
      });
      collection('/inventory', (row) {
        read('/inventory/${row['id']}');
        read('/inventory/${row['id']}/transactions');
      });
      collection('/receipts', (row) {
        read('/receipts/${row['id']}');
      });
      for (final path in [
        '/incomes',
        '/events/school-years',
        '/inventory/low-stock',
        '/analytics/dashboard',
        '/analytics/threats',
        '/notifications/unread-count',
      ]) {
        read(path);
      }
      read('/analytics/spending-trends', query: {'months': '6'});
      final now = DateTime.now();
      final month = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      read(
        '/reports/financial',
        query: {'period': 'monthly', 'reference_date': month},
      );
      pdf(
        '/reports/financial/export',
        query: {'period': 'monthly', 'reference_date': month, 'format': 'pdf'},
      );
      pdf('/reports/dashboard/export', query: {'format': 'pdf'});
      add(() async {
        final rows = <dynamic>[];
        for (var offset = 0; current(); offset += 100) {
          final query = {'limit': '100', 'offset': '$offset'};
          final previous = await store.read(
            OfflineStore.key('/notifications', query),
          );
          final page =
              (previous != null && !previous.savedAt.isBefore(started)
                      ? previous.data
                      : await api.get(
                          '/notifications',
                          query: query,
                          policy: ReadPolicy.networkOnly,
                        ))
                  as List;
          rows.addAll(page);
          if (page.length < 100) {
            if (current())
              await store.put('/notifications', rows, generation: generation);
            return;
          }
        }
      });
    }
    if (role.canAccessProposalLetters) {
      collection('/proposal-letters', (row) {
        read('/proposal-letters/${row['id']}');
        if (role == UserRole.sdsStaff) {
          final path =
              '/events/${row['event_id']}/sap-proposal/final-signed-copy';
          add(() => file('', '/proposal-letters/${row['id']}', linkPath: path));
        }
      });
    }
    for (final key in await store.keys()) {
      final uri = Uri.parse(key);
      if (uri.path == '/reports/financial' && uri.hasQuery) {
        read(uri.path, query: uri.queryParameters);
        pdf(
          '${uri.path}/export',
          query: {...uri.queryParameters, 'format': 'pdf'},
        );
      }
    }
    _notify();
    try {
      // Batches also bound dynamically discovered details and file downloads.
      while (_jobs.isNotEmpty && current()) {
        final count = _jobs.length < 3 ? _jobs.length : 3;
        final batch = _jobs.sublist(0, count);
        _jobs.removeRange(0, count);
        await Future.wait(
          batch.map((job) async {
            try {
              await job();
            } on ApiException catch (e) {
              // Missing optional resources and role refusals are not failed downloads.
              if (!e.isNotFound && !e.isForbidden) failed++;
            } catch (_) {
              failed++;
            }
            completed++;
            _notify();
          }),
        );
      }
      if (current() && failed == 0 && store.error == null) {
        lastCompleted = DateTime.now().toUtc();
        await store.setMetadata(
          'prepared_at',
          lastCompleted!.toIso8601String(),
          generation: generation,
        );
        await store.setMetadata(
          'sync_started_at',
          null,
          generation: generation,
        );
      } else if (failed == 0) {
        failed = 1;
      }
    } finally {
      running = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
