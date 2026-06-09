import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'auth_store.dart';

/// Non-2xx response from the backend.
class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);
  @override
  String toString() => 'ApiException($statusCode): $body';
}

/// Thin JSON client over the FastAPI backend. Auth is deferred for v0
/// (single user), so there are no auth headers yet — the seam to add a
/// `Authorization: Bearer` lives in [_headers].
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? AppConfig.apiBase;

  final http.Client _client;
  final String baseUrl;

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (AuthStore.token != null) 'Authorization': 'Bearer ${AuthStore.token}',
      };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: {
      ...base.queryParameters,
      for (final e in query.entries) e.key: '${e.value}',
    });
  }

  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async {
    final res = await _client.get(_uri(path, query), headers: _headers());
    return _decode(res);
  }

  /// GET returning the raw response body as text (for exports — md/csv, not JSON).
  Future<String> getText(String path, {Map<String, dynamic>? query}) async {
    final res = await _client.get(_uri(path, query), headers: _headers());
    if (res.statusCode == 401 && AuthStore.token != null) {
      AuthStore.onUnauthorized?.call();
    }
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return utf8.decode(res.bodyBytes);
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    final res = await _client.post(_uri(path),
        headers: _headers(json: true), body: jsonEncode(body));
    return _decode(res);
  }

  Future<dynamic> putJson(String path, Map<String, dynamic> body) async {
    final res = await _client.put(_uri(path),
        headers: _headers(json: true), body: jsonEncode(body));
    return _decode(res);
  }

  Future<dynamic> patchJson(String path, Map<String, dynamic> body) async {
    final res = await _client.patch(_uri(path),
        headers: _headers(json: true), body: jsonEncode(body));
    return _decode(res);
  }

  Future<void> deleteJson(String path) async {
    final res = await _client.delete(_uri(path), headers: _headers());
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
  }

  dynamic _decode(http.Response res) {
    // Token expired/invalid while we had one → let the app bounce to login.
    if (res.statusCode == 401 && AuthStore.token != null) {
      AuthStore.onUnauthorized?.call();
    }
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  void close() => _client.close();
}
