import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'auth_store.dart';

const int _maxLoggedBodyBytes = 64 * 1024;

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
  ApiClient({
    http.Client? client,
    String? baseUrl,
    bool enableLogging = kDebugMode,
  }) : _client = _wrapClient(client ?? http.Client(), enableLogging),
       baseUrl = baseUrl ?? AppConfig.apiBase;

  final http.Client _client;
  final String baseUrl;

  static http.Client _wrapClient(http.Client client, bool enableLogging) {
    if (!enableLogging || client is _ApiLoggingClient) return client;
    return _ApiLoggingClient(client);
  }

  Map<String, String> _headers({bool json = false}) => {
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
    if (AuthStore.token != null) 'Authorization': 'Bearer ${AuthStore.token}',
  };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        for (final e in query.entries) e.key: '${e.value}',
      },
    );
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
    final res = await _client.post(
      _uri(path),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<dynamic> putJson(String path, Map<String, dynamic> body) async {
    final res = await _client.put(
      _uri(path),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<dynamic> patchJson(String path, Map<String, dynamic> body) async {
    final res = await _client.patch(
      _uri(path),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
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

class _ApiLoggingClient extends http.BaseClient {
  _ApiLoggingClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sw = Stopwatch()..start();
    try {
      final res = await _inner.send(request);
      if (_shouldSkipBody(res)) {
        _logExchange(
          request: request,
          response: res,
          elapsed: sw.elapsed,
          responseBodyNote: _skipReason(res),
        );
        return res;
      }

      final bytes = await res.stream.toBytes();
      if (bytes.length > _maxLoggedBodyBytes) {
        _logExchange(
          request: request,
          response: res,
          elapsed: sw.elapsed,
          responseBodyNote: 'body ${bytes.length}B > ${_maxLoggedBodyBytes}B',
        );
      } else {
        _logExchange(
          request: request,
          response: res,
          elapsed: sw.elapsed,
          responseBody: utf8.decode(bytes, allowMalformed: true),
        );
      }
      return http.StreamedResponse(
        http.ByteStream.fromBytes(bytes),
        res.statusCode,
        contentLength: res.contentLength,
        request: res.request,
        headers: res.headers,
        isRedirect: res.isRedirect,
        persistentConnection: res.persistentConnection,
        reasonPhrase: res.reasonPhrase,
      );
    } catch (e) {
      _logFailure(request: request, elapsed: sw.elapsed, error: e);
      rethrow;
    } finally {
      sw.stop();
    }
  }

  @override
  void close() => _inner.close();

  bool _shouldSkipBody(http.StreamedResponse res) {
    final contentLength = res.contentLength;
    if (contentLength != null && contentLength > _maxLoggedBodyBytes) {
      return true;
    }

    final disposition = res.headers['content-disposition']?.toLowerCase() ?? '';
    if (disposition.contains('attachment')) return true;

    final contentType = res.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('text/event-stream')) return true;
    if (contentType.startsWith('image/') ||
        contentType.startsWith('audio/') ||
        contentType.startsWith('video/')) {
      return true;
    }
    if (contentType.contains('application/octet-stream') ||
        contentType.contains('application/pdf') ||
        contentType.contains('application/zip') ||
        contentType.contains('application/gzip')) {
      return true;
    }
    return false;
  }

  String _skipReason(http.StreamedResponse res) {
    final contentLength = res.contentLength;
    if (contentLength != null && contentLength > _maxLoggedBodyBytes) {
      return 'content-length ${contentLength}B > ${_maxLoggedBodyBytes}B';
    }

    final disposition = res.headers['content-disposition'];
    if (disposition != null &&
        disposition.toLowerCase().contains('attachment')) {
      return 'attachment';
    }

    final contentType = res.headers['content-type'];
    if (contentType == null || contentType.isEmpty) return 'body skipped';
    return 'content-type $contentType';
  }

  void _logExchange({
    required http.BaseRequest request,
    required http.StreamedResponse response,
    required Duration elapsed,
    String? responseBody,
    String? responseBodyNote,
  }) {
    final lines = <String>[
      '',
      '[API] ============================================================',
      '[API] ${request.method} ${request.url}',
      '[API] Status: ${response.statusCode}${_reasonPhrase(response)}',
      '[API] Duration: ${elapsed.inMilliseconds}ms',
      '[API] ---------------------------- Request -----------------------',
      '[API] URL: ${request.url}',
      '[API] Method: ${request.method}',
      '[API] Query:',
      ..._prefixedMapLines(request.url.queryParametersAll),
      '[API] Headers:',
      ..._prefixedMapLines(request.headers),
      '[API] Body:',
      ..._prefixedBodyLines(_requestBody(request)),
      '[API] ---------------------------- Response ----------------------',
      '[API] Headers:',
      ..._prefixedMapLines(response.headers),
      '[API] Raw Body:',
      ..._prefixedBodyLines(responseBody ?? '[$responseBodyNote]'),
      '[API] ============================================================',
    ];
    debugPrint(lines.join('\n'));
  }

  void _logFailure({
    required http.BaseRequest request,
    required Duration elapsed,
    required Object error,
  }) {
    final lines = <String>[
      '',
      '[API] ============================================================',
      '[API] ${request.method} ${request.url}',
      '[API] Status: REQUEST_FAILED',
      '[API] Duration: ${elapsed.inMilliseconds}ms',
      '[API] ---------------------------- Request -----------------------',
      '[API] URL: ${request.url}',
      '[API] Method: ${request.method}',
      '[API] Query:',
      ..._prefixedMapLines(request.url.queryParametersAll),
      '[API] Headers:',
      ..._prefixedMapLines(request.headers),
      '[API] Body:',
      ..._prefixedBodyLines(_requestBody(request)),
      '[API] ---------------------------- Error -------------------------',
      '[API] $error',
      '[API] ============================================================',
    ];
    debugPrint(lines.join('\n'));
  }

  String _reasonPhrase(http.StreamedResponse response) {
    final phrase = response.reasonPhrase;
    if (phrase == null || phrase.isEmpty) return '';
    return ' $phrase';
  }

  String _requestBody(http.BaseRequest request) {
    if (request is http.Request) {
      final bodyBytes = request.bodyBytes;
      if (bodyBytes.isEmpty) return '[empty]';
      if (bodyBytes.length > _maxLoggedBodyBytes) {
        return '[body ${bodyBytes.length}B > ${_maxLoggedBodyBytes}B]';
      }
      return utf8.decode(bodyBytes, allowMalformed: true);
    }

    if (request is http.MultipartRequest) {
      final lines = <String>[
        'multipart/form-data',
        'fields:',
        ..._plainMapLines(request.fields),
        'files:',
      ];
      if (request.files.isEmpty) {
        lines.add('  [empty]');
      } else {
        for (final file in request.files) {
          lines.add(
            '  ${file.field}: filename=${file.filename ?? '[none]'}, '
            'contentType=${file.contentType}, length=${file.length}B',
          );
        }
      }
      return lines.join('\n');
    }

    final contentLength = request.contentLength;
    if (contentLength == null || contentLength == 0) return '[empty]';
    return '[streamed request body, content-length ${contentLength}B]';
  }

  List<String> _prefixedMapLines(Map<String, dynamic> values) {
    if (values.isEmpty) return const ['[API]   [empty]'];
    return _plainMapLines(values).map((line) => '[API]   $line').toList();
  }

  List<String> _plainMapLines(Map<String, dynamic> values) {
    if (values.isEmpty) return const ['  [empty]'];
    return values.entries.map((entry) {
      final value = entry.value;
      final rendered = value is Iterable ? value.join(', ') : '$value';
      return '${entry.key}: $rendered';
    }).toList();
  }

  List<String> _prefixedBodyLines(String body) {
    if (body.isEmpty) return const ['[API]   [empty]'];
    return body.split('\n').map((line) => '[API]   $line').toList();
  }
}
