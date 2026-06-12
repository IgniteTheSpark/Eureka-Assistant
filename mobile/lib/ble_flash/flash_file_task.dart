enum FlashFileSource { realtime, offline }

enum FlashFileStage {
  discovered,
  queued,
  syncingFromCard,
  syncedToPhone,
  convertingToMp3,
  converted,
  requestingS3Presign,
  uploadingToS3,
  s3Uploaded,
  notifyingEureka,
  eurekaAccepted,
  waitingServerAsr,
  deletingDeviceFile,
  waitingServer,
  done,
  failed,
}

bool isFlashFileName(String fileName) {
  return fileName.startsWith('F') && fileName.toLowerCase().endsWith('.opus');
}

class FlashFileTask {
  const FlashFileTask({
    required this.id,
    required this.key,
    required this.deviceSn,
    required this.fileName,
    required this.source,
    required this.stage,
    required this.updatedAt,
    this.createTime,
    this.endTime,
    this.crc,
    this.deviceSizeBytes,
    this.localOpusPath,
    this.localMp3Path,
    this.mp3Sha256,
    this.mp3SizeBytes,
    this.s3Key,
    this.s3UploadUrl,
    this.s3AudioUrl,
    this.s3UploadHeaders,
    this.s3ExpiresIn,
    this.tencentAsrTaskId,
    this.eurekaRecordingId,
    this.attemptsByStage = const {},
    this.retryAfter,
    this.deviceDeletePending = false,
    this.lastError,
  });

  final String id;
  final String key;
  final String deviceSn;
  final String fileName;
  final FlashFileSource source;
  final FlashFileStage stage;
  final DateTime updatedAt;
  final int? createTime;
  final int? endTime;
  final int? crc;
  final int? deviceSizeBytes;
  final String? localOpusPath;
  final String? localMp3Path;
  final String? mp3Sha256;
  final int? mp3SizeBytes;
  final String? s3Key;
  final String? s3UploadUrl;
  final String? s3AudioUrl;
  final Map<String, String>? s3UploadHeaders;
  final int? s3ExpiresIn;
  final String? tencentAsrTaskId;
  final String? eurekaRecordingId;
  final Map<String, int> attemptsByStage;
  final DateTime? retryAfter;
  final bool deviceDeletePending;
  final String? lastError;

  FlashFileTask copyWith({
    FlashFileStage? stage,
    int? createTime,
    int? endTime,
    int? crc,
    int? deviceSizeBytes,
    String? localOpusPath,
    String? localMp3Path,
    String? mp3Sha256,
    int? mp3SizeBytes,
    String? s3Key,
    String? s3UploadUrl,
    String? s3AudioUrl,
    Map<String, String>? s3UploadHeaders,
    int? s3ExpiresIn,
    String? tencentAsrTaskId,
    String? eurekaRecordingId,
    Map<String, int>? attemptsByStage,
    DateTime? retryAfter,
    bool? deviceDeletePending,
    String? lastError,
  }) {
    return FlashFileTask(
      id: id,
      key: key,
      deviceSn: deviceSn,
      fileName: fileName,
      source: source,
      stage: stage ?? this.stage,
      updatedAt: DateTime.now(),
      createTime: createTime ?? this.createTime,
      endTime: endTime ?? this.endTime,
      crc: crc ?? this.crc,
      deviceSizeBytes: deviceSizeBytes ?? this.deviceSizeBytes,
      localOpusPath: localOpusPath ?? this.localOpusPath,
      localMp3Path: localMp3Path ?? this.localMp3Path,
      mp3Sha256: mp3Sha256 ?? this.mp3Sha256,
      mp3SizeBytes: mp3SizeBytes ?? this.mp3SizeBytes,
      s3Key: s3Key ?? this.s3Key,
      s3UploadUrl: s3UploadUrl ?? this.s3UploadUrl,
      s3AudioUrl: s3AudioUrl ?? this.s3AudioUrl,
      s3UploadHeaders: s3UploadHeaders ?? this.s3UploadHeaders,
      s3ExpiresIn: s3ExpiresIn ?? this.s3ExpiresIn,
      tencentAsrTaskId: tencentAsrTaskId ?? this.tencentAsrTaskId,
      eurekaRecordingId: eurekaRecordingId ?? this.eurekaRecordingId,
      attemptsByStage: attemptsByStage ?? this.attemptsByStage,
      retryAfter: retryAfter,
      deviceDeletePending: deviceDeletePending ?? this.deviceDeletePending,
      lastError: lastError,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'key': key,
    'deviceSn': deviceSn,
    'fileName': fileName,
    'source': source.name,
    'stage': stage.name,
    'updatedAt': updatedAt.toIso8601String(),
    'createTime': createTime,
    'endTime': endTime,
    'crc': crc,
    'deviceSizeBytes': deviceSizeBytes,
    'localOpusPath': localOpusPath,
    'localMp3Path': localMp3Path,
    'mp3Sha256': mp3Sha256,
    'mp3SizeBytes': mp3SizeBytes,
    's3Key': s3Key,
    's3UploadUrl': s3UploadUrl,
    's3AudioUrl': s3AudioUrl,
    's3UploadHeaders': s3UploadHeaders,
    's3ExpiresIn': s3ExpiresIn,
    'tencentAsrTaskId': tencentAsrTaskId,
    'eurekaRecordingId': eurekaRecordingId,
    'attemptsByStage': attemptsByStage,
    'retryAfter': retryAfter?.toIso8601String(),
    'deviceDeletePending': deviceDeletePending,
    'lastError': lastError,
  };

  static FlashFileTask fromJson(Map<String, dynamic> json) {
    T enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    return FlashFileTask(
      id: json['id'] as String,
      key: json['key'] as String,
      deviceSn: json['deviceSn'] as String,
      fileName: json['fileName'] as String,
      source: enumByName(
        FlashFileSource.values,
        json['source'] as String?,
        FlashFileSource.offline,
      ),
      stage: enumByName(
        FlashFileStage.values,
        json['stage'] as String?,
        FlashFileStage.queued,
      ),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      createTime: (json['createTime'] as num?)?.toInt(),
      endTime: (json['endTime'] as num?)?.toInt(),
      crc: (json['crc'] as num?)?.toInt(),
      deviceSizeBytes: (json['deviceSizeBytes'] as num?)?.toInt(),
      localOpusPath: json['localOpusPath'] as String?,
      localMp3Path: json['localMp3Path'] as String?,
      mp3Sha256: json['mp3Sha256'] as String?,
      mp3SizeBytes: (json['mp3SizeBytes'] as num?)?.toInt(),
      s3Key: json['s3Key'] as String?,
      s3UploadUrl: json['s3UploadUrl'] as String?,
      s3AudioUrl: json['s3AudioUrl'] as String?,
      s3UploadHeaders: (json['s3UploadHeaders'] as Map?)?.map(
        (k, v) => MapEntry('$k', '$v'),
      ),
      s3ExpiresIn: (json['s3ExpiresIn'] as num?)?.toInt(),
      tencentAsrTaskId: json['tencentAsrTaskId'] as String?,
      eurekaRecordingId: json['eurekaRecordingId'] as String?,
      attemptsByStage:
          (json['attemptsByStage'] as Map?)?.map(
            (k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0),
          ) ??
          const {},
      retryAfter: DateTime.tryParse(json['retryAfter'] as String? ?? ''),
      deviceDeletePending: json['deviceDeletePending'] == true,
      lastError: json['lastError'] as String?,
    );
  }
}
