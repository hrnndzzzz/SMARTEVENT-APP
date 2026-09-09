import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin HTTP wrapper for talking to the SmartEvent backend.
///
/// Base URL is set to the local backend tunneled over USB via
/// `adb reverse tcp:8000 tcp:8000` — see the project's dev setup notes.
/// Swap this to a real deployed URL once one exists; nothing else in
/// the app needs to change.
class ApiClient {
  static const String baseUrl = 'http://127.0.0.1:8000';

  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> get _authHeaders =>
      _token == null ? {} : {'Authorization': 'Bearer $_token'};

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  /// Throws [ApiException] on any non-2xx response, with the backend's
  /// own error detail message when available (FastAPI's standard
  /// {"detail": "..."} error shape).
  dynamic _handleResponse(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    String message = 'Request failed ($status)';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] != null) {
        message = body['detail'].toString();
      }
    } catch (_) {
      // Response wasn't JSON (e.g. a raw 500 HTML page) — keep the
      // generic message above rather than crashing on the parse.
    }
    throw ApiException(status, message);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final response = await http.get(_uri(path, query), headers: _authHeaders);
    return _handleResponse(response);
  }

  Future<dynamic> post(String path, {Object? body, bool isForm = false}) async {
    final headers = {..._authHeaders};
    late final Object encodedBody;
    if (isForm) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      encodedBody = body as String;
    } else {
      headers['Content-Type'] = 'application/json';
      encodedBody = body == null ? '' : jsonEncode(body);
    }
    final response = await http.post(_uri(path), headers: headers, body: encodedBody);
    return _handleResponse(response);
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final headers = {..._authHeaders, 'Content-Type': 'application/json'};
    final response = await http.patch(_uri(path), headers: headers, body: body == null ? '' : jsonEncode(body));
    return _handleResponse(response);
  }

  Future<void> delete(String path) async {
    final response = await http.delete(_uri(path), headers: _authHeaders);
    _handleResponse(response);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}