import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:crypto/crypto.dart';

import 'api_config.dart';
import 'token_store.dart';
import '../offline/offline_store.dart';

enum ReadPolicy { automatic, cacheOnly, networkOnly }

class ReadStamp {
  const ReadStamp(this.savedAt, this.fromCache);
  final DateTime savedAt;
  final bool fromCache;
}

/// Thin HTTP wrapper for talking to the SMARTEVENT backend.
///
/// The base URL comes from [ApiConfig], set per environment with
/// `--dart-define=SMARTEVENT_API_BASE_URL=...` — it is deliberately not a
/// constant in this file any more.
///
/// Failures are classified, never swallowed: a non-2xx response becomes an
/// [ApiException] carrying the backend's own `detail`, and an unreachable
/// server becomes a [NetworkException]. Callers are expected to tell those
/// apart — "wrong password" and "backend not running" are different
/// problems and must not show the same message.
class ApiClient {
  ApiClient({
    TokenStore? tokenStore,
    http.Client? httpClient,
    this.onReachability,
    this.onSessionExpired,
    this.offlineStore,
    this.onChanged,
    this.timeout = const Duration(seconds: 20),
  }) : _tokenStore = tokenStore ?? TokenStore(),
       _httpClient = httpClient ?? http.Client();

  /// Told whether the backend answered, after every request. An error
  /// status still counts as reachable: the server is there, it just said
  /// no. Only a failure to reach it at all is `false`.
  void Function({required bool reachable})? onReachability;
  OfflineStore? offlineStore;
  void Function()? onChanged;
  bool readOnly = false;
  bool requiresSignIn = false;
  int _epoch = 0;
  final Map<String, ReadStamp> readStamps = {};
  bool get hasOfflineSession => offlineStore?.session?.backend == baseUrl;
  bool get canWriteRemote => !readOnly && !requiresSignIn;

  void invalidateSession() {
    _epoch++;
    readOnly = true;
    readStamps.clear();
  }

  static bool cacheable(String path) =>
      RegExp(
        r'^/(events|expenses|incomes|receipts|inventory|categories|notifications|proposal-letters|analytics|reports|recommendations|departments|organizations)(/|$)',
      ).hasMatch(path) &&
      !path.endsWith('/download') &&
      !path.endsWith('/final-signed-copy') &&
      !path.endsWith('/pdf') &&
      !path.endsWith('/export');

  /// Successful writes so far. Screens that show "last changed by" watch it
  /// to refetch once their own change has landed.
  int writeCount = 0;

  Future<dynamic> _counted(Future<dynamic> write) async {
    final result = await write;
    writeCount++;
    return result;
  }

  void _guardWrite(String path) {
    _refuseInDemo();
    final publicAuth = path.startsWith('/auth/') && !hasOfflineSession;
    if (!canWriteRemote && !publicAuth && path != '/auth/login') {
      throw const OfflineUnavailable(
        'Viewing saved data. Connect and sign in before making changes.',
      );
    }
  }

  /// No server to talk to, and no pretending there is.
  ///
  /// The demo fills the app from the device. Most of what it shows is
  /// already handled without a request, but the app has dozens of calls
  /// and guarding each one is how a leak survives. So the client itself
  /// refuses while exploring, and every path gets the same honest
  /// message instead of "could not reach the backend".
  bool demoMode = false;

  /// Called when a request that carried a token comes back 401.
  ///
  /// That is the one unambiguous reading of a 401: the token the request
  /// was made with is no longer accepted. A signed-out client getting a
  /// 401 from the login route means something else entirely — wrong
  /// password — which is why this only fires when a token was attached.
  void Function()? onSessionExpired;

  final TokenStore _tokenStore;
  final http.Client _httpClient;

  /// How long one request may take before it counts as unreachable. The
  /// old client had no timeout at all, so a silently dropped connection
  /// left a spinner up indefinitely.
  final Duration timeout;

  String? _token;

  String get baseUrl => ApiConfig.baseUrl;

  bool get hasToken => _token != null;

  /// Loads a token persisted by an earlier session into memory. Returns it,
  /// or null when nothing is stored. A returned token is not proof that it
  /// is still valid — the caller should confirm with `GET /auth/me`, since
  /// the JWT may have expired or the account may have been suspended.
  Future<String?> restoreToken() async {
    final epoch = _epoch;
    final token = await _tokenStore.read();
    if (epoch != _epoch) throw const SessionChanged();
    _token = token;
    return _token;
  }

  /// Sets the in-memory token and persists it (or clears both, for null).
  Future<void> setToken(String? token) async {
    _epoch++;
    _token = token;
    if (token == null) {
      await _tokenStore.clear();
    } else {
      await _tokenStore.write(token);
    }
  }

  Map<String, String> get _authHeaders =>
      _token == null ? {} : {'Authorization': 'Bearer $_token'};

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  /// Thrown instead of a request while the app is exploring.
  void _refuseInDemo() {
    if (demoMode) throw const DemoUnavailable();
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    ReadPolicy policy = ReadPolicy.automatic,
  }) async {
    _refuseInDemo();
    final epoch = _epoch;
    final store = hasOfflineSession ? offlineStore : null;
    final cached = cacheable(path) && store != null;
    final key = OfflineStore.key(path, query);
    Future<dynamic> saved() async {
      final snapshot = cached ? await store.readRequest(path, query) : null;
      if (epoch != _epoch) throw const SessionChanged();
      if (snapshot == null) throw const OfflineUnavailable();
      readStamps[key] = ReadStamp(snapshot.savedAt, true);
      return snapshot.data;
    }

    if (policy == ReadPolicy.cacheOnly ||
        (policy == ReadPolicy.automatic &&
            readOnly &&
            !path.startsWith('/auth/'))) {
      return saved();
    }
    final generation = store?.generation;
    try {
      final data = await _send(
        () => _httpClient.get(_uri(path, query), headers: _authHeaders),
      );
      if (epoch != _epoch) throw const SessionChanged();
      if (cached) {
        try {
          final previous = await store.read(key);
          await store.put(key, data, generation: generation);
          if (epoch == _epoch &&
              (query == null || query.isEmpty) &&
              previous?.data is List &&
              data is List) {
            await store.prune(path, previous!.data as List, data);
          }
        } catch (e) {
          store.error = 'Could not save offline data: $e';
        }
      }
      if (epoch != _epoch) throw const SessionChanged();
      readStamps[key] = ReadStamp(DateTime.now().toUtc(), false);
      return data;
    } on ApiException catch (e) {
      if (epoch != _epoch) throw const SessionChanged();
      if (cached && (e.isForbidden || e.isNotFound)) await store.remove(path);
      if (policy == ReadPolicy.automatic &&
          cached &&
          (e.isServerError || e.isUnauthorized)) {
        readOnly = true;
        onChanged?.call();
        return saved();
      }
      rethrow;
    } on NetworkException {
      if (epoch != _epoch) throw const SessionChanged();
      readOnly = hasOfflineSession;
      onChanged?.call();
      if (policy == ReadPolicy.automatic && cached) return saved();
      rethrow;
    }
  }

  /// [patience] overrides the client's usual allowance for one call.
  /// Sign-in needs it: it verifies a password hash, which is slow on
  /// purpose, and it is usually the first request after an idle spell,
  /// so it pays for a cold connection through the pooler as well.
  Future<dynamic> post(
    String path, {
    Object? body,
    bool isForm = false,
    Duration? patience,
  }) {
    _guardWrite(path);
    final headers = {..._authHeaders};
    late final Object encodedBody;
    if (isForm) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      encodedBody = body as String;
    } else {
      headers['Content-Type'] = 'application/json';
      encodedBody = body == null ? '' : jsonEncode(body);
    }
    return _counted(
      _send(
        () => _httpClient.post(_uri(path), headers: headers, body: encodedBody),
        patience: patience,
      ),
    );
  }

  Future<dynamic> patch(String path, {Object? body}) {
    _guardWrite(path);
    final headers = {..._authHeaders, 'Content-Type': 'application/json'};
    return _counted(
      _send(
        () => _httpClient.patch(
          _uri(path),
          headers: headers,
          body: body == null ? '' : jsonEncode(body),
        ),
      ),
    );
  }

  /// PUT, for the routes that replace a record wholesale rather than
  /// amending one — logistics and the institutional route.
  Future<dynamic> put(String path, {Object? body}) {
    _guardWrite(path);
    final headers = {..._authHeaders, 'Content-Type': 'application/json'};
    return _counted(
      _send(
        () => _httpClient.put(
          _uri(path),
          headers: headers,
          body: body == null ? '' : jsonEncode(body),
        ),
      ),
    );
  }

  Future<void> delete(String path) async {
    _guardWrite(path);
    await _counted(
      _send(() => _httpClient.delete(_uri(path), headers: _authHeaders)),
    );
    await offlineStore?.remove(path);
  }

  /// Uploads a file as `multipart/form-data`.
  ///
  /// Used for receipt images and proposal-letter documents. [bytes] rather
  /// than a path so this works on web too, where there is no file system to
  /// read from.
  ///
  /// The multipart boundary and the request's own `Content-Type` are set by
  /// the request, so they are deliberately not added here.
  ///
  /// [contentType] is the *file part's* media type and matters: the backend
  /// validates `file.content_type` against an allow-list and does not sniff
  /// the extension. Omitting it makes the part default to
  /// `application/octet-stream`, which every upload route rejects.
  Future<dynamic> upload(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, String> fields = const {},
  }) async {
    _guardWrite(path);
    return _counted(_send(() async {
      final request = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(_authHeaders)
        ..fields.addAll(fields)
        ..files.add(
          http.MultipartFile.fromBytes(
            field,
            bytes,
            filename: filename,
            contentType: MediaType.parse(contentType),
          ),
        );

      // Sent through the injected client like every other method here.
      // `request.send()` would quietly make its own, which ignores any
      // client this was constructed with and, in a test, reaches the
      // real network.
      return http.Response.fromStream(await _httpClient.send(request));
      // Up to 10 MB from a phone, then storage (30 s) and, for a receipt
      // scan, OCR (30 s) on the server: twenty seconds gave up on uploads
      // that went on to succeed.
    }, patience: const Duration(seconds: 90)));
  }

  /// Fetches a binary response — an export — rather than JSON.
  ///
  /// Exports are protected, so they are fetched here with the Authorization
  /// header. Opening the URL in an external browser instead would send no
  /// token and fail, or worse, appear to work against a cached session.
  ///
  /// The response is checked before it is handed back: a non-2xx, or a body
  /// whose content type isn't what was asked for, is raised rather than
  /// returned. That is what stops a JSON error body being saved with a
  /// `.pdf` extension and only failing when someone opens it.
  Future<DownloadedFile> download(
    String path, {
    Map<String, String>? query,
    required String expectedContentType,
    String fallbackFilename = 'export',
    ReadPolicy policy = ReadPolicy.automatic,
    Duration? patience,
  }) async {
    _refuseInDemo();
    final key = OfflineStore.key(path, query);
    final store = hasOfflineSession ? offlineStore : null;
    Future<DownloadedFile> saved() async {
      final file = await store?.readFile(key);
      if (file == null)
        throw const OfflineUnavailable(
          'This file has not been downloaded. Connect to prepare it.',
        );
      return DownloadedFile(
        bytes: file.bytes,
        contentType: file.contentType,
        filename: file.filename,
      );
    }

    if (policy == ReadPolicy.cacheOnly ||
        (policy == ReadPolicy.automatic && readOnly))
      return saved();
    final epoch = _epoch;
    final generation = store?.generation;
    try {
      final file = await _downloadNetwork(
        path,
        query: query,
        expectedContentType: expectedContentType,
        fallbackFilename: fallbackFilename,
        patience: patience,
      );
      if (epoch != _epoch) throw const SessionChanged();
      if (store != null) {
        try {
          await store.putFile(
            key,
            file.bytes,
            file.contentType,
            file.filename,
            generation: generation,
            owner: path,
          );
        } catch (e) {
          store.error = 'Could not save offline file: $e';
        }
      }
      return file;
    } on NetworkException {
      readOnly = hasOfflineSession;
      onReachability?.call(reachable: false);
      onChanged?.call();
      if (policy == ReadPolicy.automatic && store != null) return saved();
      rethrow;
    } on ApiException catch (e) {
      if (e.isForbidden || e.isNotFound) await store?.remove(path);
      if (policy == ReadPolicy.automatic &&
          store != null &&
          (e.isUnauthorized || e.isServerError))
        return saved();
      rethrow;
    }
  }

  Future<DownloadedFile> _downloadNetwork(
    String path, {
    Map<String, String>? query,
    required String expectedContentType,
    required String fallbackFilename,
    Duration? patience,
  }) async {
    final http.Response response;
    final epoch = _epoch;
    try {
      response = await _httpClient
          .get(_uri(path, query), headers: _authHeaders)
          .timeout(patience ?? timeout);
    } on TimeoutException {
      throw NetworkException(
        'The backend at $baseUrl did not respond in time.',
      );
    } on http.ClientException catch (error) {
      throw NetworkException(
        'Could not reach the backend at $baseUrl.',
        cause: error.message,
      );
    } catch (error) {
      throw NetworkException(
        'Could not reach the backend at $baseUrl.',
        cause: error.toString(),
      );
    }

    if (epoch != _epoch) throw const SessionChanged();
    // An error body is JSON even when a PDF was requested, so the normal
    // handler is the right thing for a non-2xx here.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _handleResponse(response);
    }

    final actual = response.headers['content-type'] ?? '';
    if (!actual.toLowerCase().contains(expectedContentType.toLowerCase())) {
      throw ApiException(
        response.statusCode,
        'Expected $expectedContentType but the server sent '
        '${actual.isEmpty ? 'no content type' : actual}. Nothing was saved.',
      );
    }

    return DownloadedFile(
      bytes: response.bodyBytes,
      contentType: actual,
      filename:
          _filenameFrom(response.headers['content-disposition']) ??
          fallbackFilename,
    );
  }

  /// Resolve temporary links online, but address saved bytes by stable references.
  Future<DownloadedFile> storedFile(
    String reference, {
    String? linkPath,
    String? owner,
    ReadPolicy policy = ReadPolicy.automatic,
  }) async {
    _refuseInDemo();
    final key = linkPath ?? 'asset:$reference';
    final store = hasOfflineSession ? offlineStore : null;
    final saved = await store?.readFile(key);
    if (policy != ReadPolicy.networkOnly && saved != null) {
      return DownloadedFile(
        bytes: saved.bytes,
        contentType: saved.contentType,
        filename: saved.filename,
      );
    }
    if (policy == ReadPolicy.cacheOnly ||
        (policy == ReadPolicy.automatic && readOnly)) {
      throw const OfflineUnavailable(
        'This file has not been downloaded. Connect to prepare it.',
      );
    }
    final epoch = _epoch;
    final generation = store?.generation;
    final dynamic resolved;
    try {
      resolved = await get(
        linkPath ?? '/files',
        query: linkPath == null ? {'reference': reference} : null,
        policy: ReadPolicy.networkOnly,
      );
    } on ApiException catch (error) {
      if (epoch != _epoch) throw const SessionChanged();
      if (error.isForbidden || error.isNotFound) await store?.removeFile(key);
      rethrow;
    }
    final uri = Uri.parse((resolved as Map)['url'] as String);
    if (uri.scheme != 'https' && uri.scheme != 'http')
      throw const FormatException('Invalid download address');
    final http.Response response;
    try {
      // Signed storage URLs are credentials themselves; never attach our API token.
      response = await _httpClient.get(uri).timeout(timeout);
    } catch (e) {
      throw NetworkException(
        'The file could not be downloaded.',
        cause: e.toString(),
      );
    }
    if (epoch != _epoch) throw const SessionChanged();
    if (response.statusCode != 200)
      throw ApiException(
        response.statusCode,
        'The file download failed. Try again online.',
      );
    final mime =
        response.headers['content-type']?.split(';').first.toLowerCase() ?? '';
    if (!mime.startsWith('image/') && mime != 'application/pdf') {
      throw ApiException(200, 'The server did not return an image or PDF.');
    }
    final digest = resolved['sha256'];
    if (digest is String &&
        digest.isNotEmpty &&
        sha256.convert(response.bodyBytes).toString() != digest.toLowerCase()) {
      throw const FormatException(
        'The downloaded file failed its integrity check.',
      );
    }
    final file = DownloadedFile(
      bytes: response.bodyBytes,
      contentType: mime,
      filename:
          _filenameFrom(response.headers['content-disposition']) ??
          (mime == 'application/pdf'
              ? 'document.pdf'
              : 'image.${mime.split('/').last}'),
    );
    if (store != null) {
      await store.putFile(
        key,
        file.bytes,
        mime,
        file.filename,
        generation: generation,
        owner: owner,
      );
    }
    return file;
  }

  /// Pulls the filename out of a `Content-Disposition` header, so a saved
  /// export is named by the server rather than guessed at.
  static String? _filenameFrom(String? disposition) {
    if (disposition == null) return null;
    final match = RegExp(
      r'filename\*?=(?:UTF-8'
      ')?"?([^";]+)"?',
    ).firstMatch(disposition);
    final name = match?.group(1)?.trim();
    return (name == null || name.isEmpty) ? null : Uri.decodeFull(name);
  }

  /// Runs a request and turns every failure mode into either an
  /// [ApiException] (the server answered) or a [NetworkException] (it
  /// didn't). Nothing else escapes.
  Future<dynamic> _send(
    Future<http.Response> Function() request, {
    Duration? patience,
  }) async {
    final epoch = _epoch;
    try {
      final response = await request().timeout(patience ?? timeout);
      if (epoch != _epoch) throw const SessionChanged();
      onReachability?.call(reachable: true);
      return _handleResponse(response);
    } on SessionChanged {
      rethrow;
    } on ApiException {
      // The server answered — it just answered with a refusal.
      rethrow;
    } on TimeoutException {
      if (epoch != _epoch) throw const SessionChanged();
      readOnly = hasOfflineSession;
      onChanged?.call();
      onReachability?.call(reachable: false);
      throw NetworkException(
        'The backend at $baseUrl did not respond in time.',
      );
    } on http.ClientException catch (error) {
      if (epoch != _epoch) throw const SessionChanged();
      readOnly = hasOfflineSession;
      onChanged?.call();
      onReachability?.call(reachable: false);
      throw NetworkException(
        'Could not reach the backend at $baseUrl.',
        cause: error.message,
      );
    } catch (error) {
      onReachability?.call(reachable: false);
      // DNS, TLS and socket failures surface as different types on mobile,
      // desktop and web (SocketException, HandshakeException, browser
      // errors). Treating the remainder as "unreachable" is more useful
      // than letting an unhandled error escape into the widget tree.
      throw NetworkException(
        'Could not reach the backend at $baseUrl.',
        cause: error.toString(),
      );
    }
  }

  dynamic _handleResponse(http.Response response) {
    final status = response.statusCode;
    if (status == 401 && _token != null) {
      readOnly = true;
      requiresSignIn = true;
      onSessionExpired?.call();
    }
    if (status >= 200 && status < 300) {
      if (response.body.isEmpty) return null;
      // A 204 has no body; anything else that parses cleanly is returned.
      return jsonDecode(response.body);
    }

    Object? detail;
    try {
      final body = jsonDecode(response.body);
      if (body is Map) detail = body['detail'];
    } catch (_) {
      // Response wasn't JSON (a raw 500 HTML page, a proxy error page) —
      // fall back to the per-status message rather than crashing here.
    }

    throw ApiException(
      status,
      _messageFor(status, detail),
      fieldErrors: _fieldErrorsFor(detail),
      detail: detail,
    );
  }

  /// FastAPI's 422 body is `{"detail": [{"loc": [...], "msg": "..."}]}`.
  /// Flattening it to field -> message lets forms mark the offending
  /// inputs instead of dumping a raw list into a snackbar.
  static Map<String, String> _fieldErrorsFor(Object? detail) {
    if (detail is! List) return const {};
    final errors = <String, String>{};
    for (final entry in detail) {
      if (entry is! Map) continue;
      final message = entry['msg']?.toString();
      if (message == null || message.isEmpty) continue;
      final location = entry['loc'];
      final field = location is List
          ? location
                .where(
                  (part) => part != 'body' && part != 'query' && part != 'path',
                )
                .join('.')
          : '';
      errors[field.isEmpty ? _generalFieldKey : field] = message;
    }
    return errors;
  }

  /// Key used for a validation message that isn't tied to a single field.
  static const String _generalFieldKey = '_';

  static String _messageFor(int status, Object? detail) {
    // The backend's own explanation is always the most specific thing we
    // have — prefer it over any message invented here.
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();

    // Some refusals are objects: `{message, blockers}` for compliance,
    // `{code, detail}` for a duplicate receipt.
    if (detail is Map) {
      final text = detail['message'] ?? detail['detail'];
      final blockers = detail['blockers'];
      if (text is String && text.trim().isNotEmpty) {
        return [text.trim(), if (blockers is List) ...blockers].join('\n');
      }
    }

    final fieldErrors = _fieldErrorsFor(detail);
    if (fieldErrors.isNotEmpty) {
      return fieldErrors.entries
          .map(
            (e) => e.key == _generalFieldKey ? e.value : '${e.key}: ${e.value}',
          )
          .join('\n');
    }

    return switch (status) {
      400 => 'That request was rejected. Check the values and try again.',
      401 => 'Your session is no longer valid. Sign in again.',
      403 => 'Your role or department scope does not allow this action.',
      404 => 'That record is no longer available.',
      409 => 'That conflicts with the current state of the record.',
      422 => 'Some fields need fixing before this can be saved.',
      502 || 503 =>
        'A service the backend depends on (storage, OCR or email) is '
            'unavailable. Your input was kept — try again shortly.',
      _ =>
        status >= 500
            ? 'The backend ran into a problem ($status). Nothing was saved.'
            : 'Request failed ($status).',
    };
  }
}

class OfflineUnavailable implements Exception {
  const OfflineUnavailable([
    this.message =
        'Not downloaded yet. Connect to prepare this data for offline viewing.',
  ]);
  final String message;
  @override
  String toString() => message;
}

class SessionChanged implements Exception {
  const SessionChanged();
  @override
  String toString() => 'The account or server changed. Open this screen again.';
}

/// The server answered with a non-2xx status. [message] is the backend's own
/// `detail` when it sent one, so it is safe to show to the user as text.
/// Raised when the app is exploring with seeded data and something
/// asked for the network anyway.
class DemoUnavailable implements Exception {
  const DemoUnavailable();

  @override
  String toString() => 'Not available while exploring.';
}

class ApiException implements Exception {
  ApiException(
    this.statusCode,
    this.message, {
    this.fieldErrors = const {},
    this.detail,
  });

  final int statusCode;
  final String message;

  /// The backend's own `detail`, as it was parsed.
  ///
  /// [message] and [fieldErrors] cover the two shapes FastAPI sends by
  /// default. Some routes send a structured object instead — the roster
  /// import answers a bad workbook with every bad row — and flattening
  /// that to one sentence throws away the part worth showing.
  final Object? detail;

  /// Field name -> validation message, populated for 422 responses.
  final Map<String, String> fieldErrors;

  /// Wrong credentials at sign-in, or an expired/invalid token afterwards.
  /// The caller knows which of the two it is from its own context.
  bool get isUnauthorized => statusCode == 401;

  /// Role, scope, ownership, suspension or pending password setup. Never
  /// work around this client-side; the API is the authority.
  bool get isForbidden => statusCode == 403;

  bool get isNotFound => statusCode == 404;

  /// A workflow conflict: in-use category, duplicate receipt, budget limit,
  /// already-completed purchase, self-review restriction, and so on.
  bool get isConflict => statusCode == 409;

  bool get isValidationError => statusCode == 422;

  /// Storage, OCR or email is down. Preserve the user's input and retry.
  bool get isServiceUnavailable => statusCode == 502 || statusCode == 503;

  bool get isServerError => statusCode >= 500;

  /// True when retrying the exact same request could plausibly succeed.
  /// Deliberately excludes 5xx on writes — the caller must check the list
  /// before resending a financial write rather than retrying blindly.
  bool get isRetryable => isServiceUnavailable;

  @override
  String toString() => message;
}

/// The request never got an answer: no network, wrong host or port, backend
/// not running, DNS or TLS failure, or a timeout. Distinct from
/// [ApiException] because the fix is different — and because a write may or
/// may not have reached the server, so it must not be retried silently.
class NetworkException implements Exception {
  NetworkException(this.message, {this.cause});

  final String message;

  /// The underlying platform error, for diagnostics. Not shown to users.
  final String? cause;

  @override
  String toString() => message;
}

/// A downloaded export: the bytes, what they are, and what to call them.
///
/// Deliberately a value rather than a path — the caller decides whether to
/// save, share or print, and on web there is no file system to write to.
class DownloadedFile {
  DownloadedFile({
    required this.bytes,
    required this.contentType,
    required this.filename,
  });

  final List<int> bytes;

  /// As the server reported it, already checked against what was requested.
  final String contentType;

  /// From `Content-Disposition` when the server supplied one.
  final String filename;

  int get sizeBytes => bytes.length;
}
