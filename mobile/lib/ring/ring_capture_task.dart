import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

enum RingCaptureStage {
  provisional,
  recording,
  fileAssociated,
  downloading,
  downloaded,
  transcribing,
  submitting,
  accepted,
  deletingDeviceFile,
  done,
  failed,
}

String ringDeviceCaptureKey({
  String deviceKind = 'ring',
  required String deviceId,
  required String fileName,
  required List<int> fileId,
  required int sizeBytes,
}) {
  final normalizedKind = deviceKind.trim().toLowerCase();
  final normalizedDeviceId = deviceId.trim().toUpperCase();
  final normalizedFileName = fileName.trim();
  if (normalizedKind.isEmpty) {
    throw ArgumentError.value(deviceKind, 'deviceKind', 'must not be empty');
  }
  if (normalizedDeviceId.isEmpty) {
    throw ArgumentError.value(deviceId, 'deviceId', 'must not be empty');
  }
  if (normalizedFileName.isEmpty) {
    throw ArgumentError.value(fileName, 'fileName', 'must not be empty');
  }
  if (sizeBytes < 0) {
    throw ArgumentError.value(sizeBytes, 'sizeBytes', 'must not be negative');
  }
  if (fileId.any((value) => value < 0 || value > 255)) {
    throw ArgumentError.value(fileId, 'fileId', 'must contain bytes');
  }
  final canonical = jsonEncode([
    normalizedKind,
    normalizedDeviceId,
    normalizedFileName,
    List<int>.from(fileId),
    sizeBytes,
  ]);
  return '$normalizedKind:${sha256.convert(utf8.encode(canonical))}';
}

const Object _notProvided = Object();

@immutable
class RingCaptureTask {
  RingCaptureTask({
    required String id,
    required String userId,
    required String deviceId,
    required this.stage,
    required DateTime startedAt,
    required DateTime updatedAt,
    DateTime? endedAt,
    this.fileName,
    List<int> fileId = const [],
    this.deviceSizeBytes,
    this.deviceCaptureKey,
    this.localWavPath,
    this.localAudioSha256,
    this.localAudioSizeBytes,
    this.transcript,
    this.recordingId,
    this.sessionId,
    this.inputTurnId,
    this.deletePending = false,
    this.lastErrorCode,
  }) : id = _requiredString(id, 'id'),
       userId = _requiredString(userId, 'userId'),
       deviceId = _requiredString(deviceId, 'deviceId'),
       startedAt = startedAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       endedAt = endedAt?.toUtc(),
       fileId = List<int>.unmodifiable(fileId);

  final String id;
  final String userId;
  final String deviceId;
  final RingCaptureStage stage;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? endedAt;
  final String? fileName;
  final List<int> fileId;
  final int? deviceSizeBytes;
  final String? deviceCaptureKey;
  final String? localWavPath;
  final String? localAudioSha256;
  final int? localAudioSizeBytes;
  final String? transcript;
  final String? recordingId;
  final String? sessionId;
  final String? inputTurnId;
  final bool deletePending;
  final String? lastErrorCode;

  factory RingCaptureTask.fromJson(Map<String, dynamic> json) {
    try {
      final rawFileId = json['fileId'];
      final fileId = rawFileId == null
          ? const <int>[]
          : _parseFileId(rawFileId);
      return RingCaptureTask(
        id: _requiredJsonString(json, 'id'),
        userId: _requiredJsonString(json, 'userId'),
        deviceId: _requiredJsonString(json, 'deviceId'),
        stage: RingCaptureStage.values.byName(
          _requiredJsonString(json, 'stage'),
        ),
        startedAt: _requiredJsonDateTime(json, 'startedAt'),
        updatedAt: _requiredJsonDateTime(json, 'updatedAt'),
        endedAt: _optionalJsonDateTime(json, 'endedAt'),
        fileName: _optionalJsonString(json, 'fileName'),
        fileId: fileId,
        deviceSizeBytes: _optionalJsonInt(json, 'deviceSizeBytes'),
        deviceCaptureKey: _optionalJsonString(json, 'deviceCaptureKey'),
        localWavPath: _optionalJsonString(json, 'localWavPath'),
        localAudioSha256: _optionalJsonString(json, 'localAudioSha256'),
        localAudioSizeBytes: _optionalJsonInt(json, 'localAudioSizeBytes'),
        transcript: _optionalJsonString(json, 'transcript'),
        recordingId: _optionalJsonString(json, 'recordingId'),
        sessionId: _optionalJsonString(json, 'sessionId'),
        inputTurnId: _optionalJsonString(json, 'inputTurnId'),
        deletePending: json['deletePending'] == true,
        lastErrorCode: _optionalJsonString(json, 'lastErrorCode'),
      );
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('invalid ring capture task: $error');
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'deviceId': deviceId,
    'stage': stage.name,
    'startedAt': startedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'fileName': fileName,
    'fileId': fileId,
    'deviceSizeBytes': deviceSizeBytes,
    'deviceCaptureKey': deviceCaptureKey,
    'localWavPath': localWavPath,
    'localAudioSha256': localAudioSha256,
    'localAudioSizeBytes': localAudioSizeBytes,
    'transcript': transcript,
    'recordingId': recordingId,
    'sessionId': sessionId,
    'inputTurnId': inputTurnId,
    'deletePending': deletePending,
    'lastErrorCode': lastErrorCode,
  };

  RingCaptureTask copyWith({
    String? id,
    String? userId,
    String? deviceId,
    RingCaptureStage? stage,
    DateTime? startedAt,
    DateTime? updatedAt,
    Object? endedAt = _notProvided,
    Object? fileName = _notProvided,
    List<int>? fileId,
    Object? deviceSizeBytes = _notProvided,
    Object? deviceCaptureKey = _notProvided,
    Object? localWavPath = _notProvided,
    Object? localAudioSha256 = _notProvided,
    Object? localAudioSizeBytes = _notProvided,
    Object? transcript = _notProvided,
    Object? recordingId = _notProvided,
    Object? sessionId = _notProvided,
    Object? inputTurnId = _notProvided,
    bool? deletePending,
    Object? lastErrorCode = _notProvided,
  }) {
    return RingCaptureTask(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      stage: stage ?? this.stage,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      endedAt: _nullableValue<DateTime>(endedAt, this.endedAt),
      fileName: _nullableValue<String>(fileName, this.fileName),
      fileId: fileId ?? this.fileId,
      deviceSizeBytes: _nullableValue<int>(
        deviceSizeBytes,
        this.deviceSizeBytes,
      ),
      deviceCaptureKey: _nullableValue<String>(
        deviceCaptureKey,
        this.deviceCaptureKey,
      ),
      localWavPath: _nullableValue<String>(localWavPath, this.localWavPath),
      localAudioSha256: _nullableValue<String>(
        localAudioSha256,
        this.localAudioSha256,
      ),
      localAudioSizeBytes: _nullableValue<int>(
        localAudioSizeBytes,
        this.localAudioSizeBytes,
      ),
      transcript: _nullableValue<String>(transcript, this.transcript),
      recordingId: _nullableValue<String>(recordingId, this.recordingId),
      sessionId: _nullableValue<String>(sessionId, this.sessionId),
      inputTurnId: _nullableValue<String>(inputTurnId, this.inputTurnId),
      deletePending: deletePending ?? this.deletePending,
      lastErrorCode: _nullableValue<String>(lastErrorCode, this.lastErrorCode),
    );
  }
}

T? _nullableValue<T>(Object? value, T? current) {
  return identical(value, _notProvided) ? current : value as T?;
}

String _requiredString(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw FormatException('$field must not be empty');
  return normalized;
}

String _requiredJsonString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String) throw FormatException('$field must be a string');
  return _requiredString(value, field);
}

String? _optionalJsonString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is! String) throw FormatException('$field must be a string');
  return value;
}

int? _optionalJsonInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is! int) throw FormatException('$field must be an integer');
  return value;
}

DateTime _requiredJsonDateTime(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a timestamp');
  }
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw FormatException('$field must be a valid timestamp');
  }
}

DateTime? _optionalJsonDateTime(Map<String, dynamic> json, String field) {
  if (json[field] == null) return null;
  return _requiredJsonDateTime(json, field);
}

List<int> _parseFileId(Object value) {
  if (value is! List) throw const FormatException('fileId must be a list');
  final parsed = <int>[];
  for (final item in value) {
    if (item is! int || item < 0 || item > 255) {
      throw const FormatException('fileId must contain bytes');
    }
    parsed.add(item);
  }
  return List<int>.unmodifiable(parsed);
}
