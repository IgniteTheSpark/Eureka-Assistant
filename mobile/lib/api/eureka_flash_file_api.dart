import 'package:flutter/foundation.dart';

import 'api_client.dart';

class EurekaFlashFileApi {
  EurekaFlashFileApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;
  static const _logTag = '[FlashFile]';

  void _log(String message) => debugPrint('$_logTag EurekaApi $message');

  Future<Map<String, dynamic>> notifyTencentAsrS3Upload(
    Map<String, dynamic> payload,
  ) async {
    _log(
      'notify upload request clientTask=${payload['client_task_id']} '
      'file=${payload['device_file_name']} s3Key=${(payload['s3'] as Map?)?['s3_key']}',
    );
    final res = await _api.postJson(
      '/api/flash/tencent-asr-s3-uploads',
      payload,
    );
    final map = (res as Map).cast<String, dynamic>();
    _log(
      'notify upload response accepted=${map['accepted']} duplicate=${map['duplicate']} '
      'recording=${map['recording_id']} asrStatus=${map['asr_status']} pipeline=${map['pipeline_status']}',
    );
    return map;
  }

  Future<Map<String, dynamic>> submitTencentAsrSyncResult(
    Map<String, dynamic> payload,
  ) async {
    _log(
      'submit sync ASR result request clientTask=${payload['client_task_id']} '
      'file=${payload['device_file_name']} status=${payload['asr_status']} '
      'textLen=${payload['asr_text']?.toString().length ?? 0} error=${payload['asr_error'] ?? payload['error_message'] ?? ""}',
    );
    final res = await _api.postJson(
      '/api/flash/tencent-asr-sync-results',
      payload,
    );
    final map = (res as Map).cast<String, dynamic>();
    _log(
      'submit sync ASR result response accepted=${map['accepted']} duplicate=${map['duplicate']} '
      'recording=${map['recording_id']} asrStatus=${map['asr_status']} pipeline=${map['pipeline_status']} '
      'message=${map['message']}',
    );
    return map;
  }

  Future<Map<String, dynamic>> getRecording(String recordingId) async {
    _log('get recording request recording=$recordingId');
    final res = await _api.getJson('/api/flash/recordings/$recordingId');
    final map = (res as Map).cast<String, dynamic>();
    final recording = (map['recording'] as Map?)?.cast<String, dynamic>();
    _log(
      'get recording response recording=$recordingId process=${recording?['process_status']} '
      'asr=${recording?['asr_status']} tencent=${recording?['tencent_status']}',
    );
    return map;
  }

  void close() => _api.close();
}
