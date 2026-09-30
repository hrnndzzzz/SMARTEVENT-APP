import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'api_config.dart';
import 'token_store.dart';

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
    this.timeout = const Duration(seconds: 20),
  })  : _tokenStore = tokenStore ?? TokenStore(),
        _httpClient = httpClient ?? http.Client();

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
    _token = await _tokenStore.read();
    return _token;
  }

  /// Sets the in-memory token and persists it (or clears both, for null).
  Future<void> setToken(String? token) async {
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

  Future<dynamic> get(String path, {Map<String, String>? query}) {
    return _send(() => _httpClient.get(_uri(path, query), headers: _authHeaders));
  }

  Future<dynamic> post(String path, {Object? body, bool isForm = false}) {
    final headers = {..._authHeaders};
    late final Object encodedBody;
    if (isForm) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      encodedBody = body as String;
    } else {
      headers['Content-Type'] = 'application/json';
      encodedBody = body == null ? '' : jsonEncode(body);
    }
    return _send(
      () => _httpClient.post(_uri(path), headers: headers, body: encodedBody),
    );
  }

  Future<dynamic> patch(String path, {Object? body}) {
    final headers = {..._authHeaders, 'Content-Type': 'application/json'};
    return _send(
      () => _httpClient.patch(
        _uri(path),
        headers: headers,
        body: body == null ? '' : jsonEncode(body),
      ),
    );
  }

  Future<void> delete(String path) async {
    await _send(() => _httpClient.delete(_uri(path), headers: _authHeaders));
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
    return _send(() async {
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

      return http.Response.fromStream(await request.send());
    });
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
  }) async {
    final http.Response response;
    try {
      response = await _httpClient
          .get(_uri(path, query), headers: _authHeaders)
          .timeout(timeout);
    } on TimeoutException {
      throw NetworkException('The backend at $baseUrl did not respond in time.');
    } on http.ClientException catch (error) {
      throw NetworkException('Could not reach the backend at $baseUrl.',
          cause: error.message);
    } catch (error) {
      throw NetworkException('Could not reach the backend at $baseUrl.',
          cause: error.toString());
    }

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
      filename: _filenameFrom(response.headers['content-disposition']) ??
          fallbackFilename,
    );
  }

  /// Pulls the filename out of a `Content-Disposition` header, so a saved
  /// export is named by the server rather than guessed at.
  static String? _filenameFrom(String? disposition) {
    if (disposition == null) return null;
    final match = RegExp(r'filename\*?=(?:UTF-8'')?"?([^";]+)"?')
        .firstMatch(disposition);
    final name = match?.group(1)?.trim();
    return (name == null || name.isEmpty) ? null : Uri.decodeFull(name);
  }

  /// Runs a request and turns every failure mode into either an
  /// [ApiException] (the server answered) or a [NetworkException] (it
  /// didn't). Nothing else escapes.
  Future<dynamic> _send(Future<http.Response> Function() request) async {
    try {
      final response = await request().timeout(timeout);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
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
              .where((part) => part != 'body' && part != 'query' && part != 'path')
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

    final fieldErrors = _fieldErrorsFor(detail);
    if (fieldErrors.isNotEmpty) {
      return fieldErrors.entries
          .map((e) => e.key == _generalFieldKey ? e.value : '${e.key}: ${e.value}')
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
      _ => status >= 500
          ? 'The backend ran into a problem ($status). Nothing was saved.'
          : 'Request failed ($status).',
    };
  }
}

/// The server answered with a non-2xx status. [message] is the backend's own
/// `detail` when it sent one, so it is safe to show to the user as text.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.fieldErrors = const {}});

  final int statusCode;
  final String message;

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
