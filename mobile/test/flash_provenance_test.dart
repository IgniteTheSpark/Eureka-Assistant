import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/flash/flash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sendFlash serializes trusted hardware provenance in UTC', () async {
    Map<String, dynamic>? requestBody;
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        requestBody = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        return http.Response(
          jsonEncode({
            'ok': true,
            'session_id': '',
            'recording_id': '',
            'physical_session_id': '',
            'input_turn_id': '',
            'cards': <Object>[],
            'has_pending': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);

    await sendFlash(
      api,
      '喝了五百毫升水',
      clientTaskId: 'ring-file-1',
      provenance: FlashCaptureProvenance(
        deviceCaptureKey: 'ring:stable-key',
        deviceKind: 'RING',
        deviceId: 'AA:BB',
        deviceFileName: 'R1.bin',
        captureStartedAt: DateTime.parse('2026-08-11T08:30:00+08:00'),
        captureEndedAt: DateTime.parse('2026-08-11T08:30:12+08:00'),
        localAudioSha256: 'ABCDEF',
        localAudioSizeBytes: 240000,
      ),
    );

    expect(requestBody, containsPair('device_capture_key', 'ring:stable-key'));
    expect(requestBody, containsPair('device_kind', 'ring'));
    expect(requestBody, containsPair('device_id', 'AA:BB'));
    expect(requestBody, containsPair('device_file_name', 'R1.bin'));
    expect(
      requestBody,
      containsPair('capture_started_at', '2026-08-11T00:30:00.000Z'),
    );
    expect(
      requestBody,
      containsPair('capture_ended_at', '2026-08-11T00:30:12.000Z'),
    );
    expect(requestBody, containsPair('local_audio_sha256', 'abcdef'));
    expect(requestBody, containsPair('local_audio_size_bytes', 240000));
  });

  test('sendFlash omits provenance for existing typed callers', () async {
    Map<String, dynamic>? requestBody;
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        requestBody = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        return http.Response(
          jsonEncode({
            'ok': true,
            'session_id': '',
            'recording_id': '',
            'physical_session_id': '',
            'input_turn_id': '',
            'cards': <Object>[],
            'has_pending': true,
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);

    await sendFlash(api, '手动输入', source: 'typed');

    expect(requestBody, {'text': '手动输入', 'source': 'typed'});
  });

  test('sendVoiceFlash uses the ASR session as its idempotency key', () async {
    Map<String, dynamic>? requestBody;
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        requestBody = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        return http.Response(
          jsonEncode({
            'ok': true,
            'session_id': '',
            'recording_id': '',
            'physical_session_id': '',
            'input_turn_id': '',
            'cards': <Object>[],
            'has_pending': true,
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);

    await sendVoiceFlash(api, '语音闪念', voiceSessionId: 'voice-session-42');

    expect(requestBody, {
      'text': '语音闪念',
      'source': 'voice',
      'client_task_id': 'voice-session-42',
    });
  });
}
