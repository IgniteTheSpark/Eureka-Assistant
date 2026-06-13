import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'api_client.dart';

class TencentAsrPresign {
  TencentAsrPresign({
    required this.s3Key,
    required this.uploadUrl,
    required this.audioUrl,
    required this.headers,
    required this.expiresIn,
  });

  final String s3Key;
  final String uploadUrl;
  final String audioUrl;
  final Map<String, String> headers;
  final int expiresIn;
}

class TencentAsrSyncResult {
  TencentAsrSyncResult({
    required this.text,
    required this.segments,
    required this.rawResponse,
  });

  final String text;
  final List<dynamic> segments;
  final Map<String, dynamic> rawResponse;
}

class TencentAsrS3Client {
  TencentAsrS3Client({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = (baseUrl ?? AppConfig.tencentAsrBase).replaceFirst(
        RegExp(r'/$'),
        '',
      );

  final http.Client _client;
  final String baseUrl;
  static const _logTag = '[FlashFile]';

  void _log(String message) => debugPrint('$_logTag PlatformSpeech $message');

  Future<TencentAsrPresign> createPresign({
    required String filename,
    String contentType = 'audio/mpeg',
    int expiresIn = 3600,
  }) async {
    _log(
      's3_presign request filename=$filename contentType=$contentType expiresIn=$expiresIn baseUrl=$baseUrl',
    );
    final res = await _client.post(
      Uri.parse('$baseUrl/api/platform/speech/tencent_asr/s3_presign'),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'filename': filename,
        'content_type': contentType,
        'expires_in': expiresIn,
      }),
    );
    final body = _decode(res);
    final data = (body['data'] as Map).cast<String, dynamic>();
    final headers = ((data['headers'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    );
    final presign = TencentAsrPresign(
      s3Key: data['s3_key']?.toString() ?? '',
      uploadUrl: data['upload_url']?.toString() ?? '',
      audioUrl: data['audio_url']?.toString() ?? '',
      headers: headers.isEmpty ? const {'Content-Type': 'audio/mpeg'} : headers,
      expiresIn: (data['expires_in'] as num?)?.toInt() ?? expiresIn,
    );
    _log(
      's3_presign success status=${res.statusCode} s3Key=${presign.s3Key} '
      'hasUploadUrl=${presign.uploadUrl.isNotEmpty} hasAudioUrl=${presign.audioUrl.isNotEmpty}',
    );
    return presign;
  }

  Future<void> uploadFile({
    required String uploadUrl,
    required Map<String, String> headers,
    required File file,
  }) async {
    _log('s3 PUT upload start file=${file.path} bytes=${await file.length()}');
    final res = await _client.put(
      Uri.parse(uploadUrl),
      headers: headers,
      body: await file.readAsBytes(),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _log('s3 PUT upload failed status=${res.statusCode} body=${res.body}');
      throw ApiException(res.statusCode, res.body);
    }
    _log('s3 PUT upload success status=${res.statusCode}');
  }

  Future<void> uploadMp3({
    required String uploadUrl,
    required Map<String, String> headers,
    required File file,
  }) {
    return uploadFile(uploadUrl: uploadUrl, headers: headers, file: file);
  }

  Future<TencentAsrSyncResult> recognizeFile({
    required File file,
    bool speakerDiarization = false,
  }) async {
    _log(
      'sync_asr request file=${file.path} bytes=${await file.length()} baseUrl=$baseUrl',
    );
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/platform/speech/asr'),
    );
    request.fields['speaker_diarization'] = speakerDiarization
        ? 'true'
        : 'false';
    request.files.add(await http.MultipartFile.fromPath('audio', file.path));
    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    final body = _decode(res);
    final data = (body['data'] as Map).cast<String, dynamic>();
    final result = TencentAsrSyncResult(
      text: data['text']?.toString() ?? '',
      segments: (data['segments'] as List?)?.toList() ?? const [],
      rawResponse: body,
    );
    _log(
      'sync_asr success status=${res.statusCode} textLen=${result.text.length} segments=${result.segments.length}',
    );
    return result;
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode >= 400) {
      _log(
        'platform speech http failed status=${res.statusCode} body=${res.body}',
      );
      throw ApiException(res.statusCode, res.body);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map) throw ApiException(res.statusCode, res.body);
    final map = body.cast<String, dynamic>();
    if (map['code'] != 0) {
      _log(
        'platform speech biz failed status=${res.statusCode} body=${res.body}',
      );
      throw ApiException(res.statusCode, res.body);
    }
    return map;
  }

  void close() => _client.close();
}
