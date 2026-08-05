import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/api/sse_client.dart';
import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/theme_v2/capture/capture_session_controller.dart';
import 'package:eureka/theme_v2/session/theme_v2_session_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'physical flash session loads unified transcript and sends through api chat',
    () async {
      final requests = <String>[];
      final turns = <(String, Map<String, dynamic>)>[];
      final api = ApiClient(
        baseUrl: 'http://theme-v2.test',
        enableLogging: false,
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.url.path == '/api/flash/sessions/2026-08-05') {
            return http.Response(
              jsonEncode({
                'session': {
                  'id': '2026-08-05',
                  'date': '2026-08-05',
                  'physical_session_id': 'physical-session-1',
                  'session_revision': 4,
                  'recordings': [
                    {
                      'id': 'recording-1',
                      'process_status': 'done',
                      'asr_text': '跑了两公里',
                      'input_turn_id': 'turn-voice-1',
                      'result_summary': '已记录跑步。',
                      'result_cards': const [],
                    },
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/sessions/physical-session-1/messages') {
            return http.Response(
              jsonEncode({
                'messages': [
                  {
                    'id': 'voice-user-1',
                    'role': 'user',
                    'status': 'done',
                    'text': '跑了两公里',
                    'input_turn_id': 'turn-voice-1',
                    'cards': const [],
                  },
                  {
                    'id': 'voice-agent-1',
                    'role': 'agent',
                    'status': 'done',
                    'text': '已记录跑步。',
                    'input_turn_id': 'turn-voice-1',
                    'cards': const [],
                  },
                  {
                    'id': 'typed-user-1',
                    'role': 'user',
                    'status': 'done',
                    'text': '刚才那个是多少？',
                    'input_turn_id': 'turn-typed-1',
                    'cards': const [],
                  },
                  {
                    'id': 'typed-agent-1',
                    'role': 'agent',
                    'status': 'done',
                    'text': '刚才记录的是两公里。',
                    'input_turn_id': 'turn-typed-1',
                    'cards': const [],
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      );
      final controller = CaptureSessionController(
        api: api,
        turnStream: (path, body) {
          turns.add((path, body));
          return Stream<SseEvent>.fromIterable([
            SseEvent('meta', {
              'session_id': 'physical-session-1',
              'input_turn_id': 'turn-typed-2',
            }),
            SseEvent('tool_call', {'name': 'tool_update_asset'}),
            SseEvent('tool_result', {
              'name': 'tool_update_asset',
              'response': {'ok': true, 'asset_id': 'asset-1'},
            }),
            SseEvent('token', {'text': '改好啦，跑步距离是 3 公里。'}),
            SseEvent('done', {'elapsed_ms': 120, 'total_tokens': 42}),
          ]);
        },
      );
      addTearDown(() {
        controller.dispose();
        api.close();
      });

      await controller.loadSession('2026-08-05');

      expect(requests, [
        'GET /api/flash/sessions/2026-08-05',
        'GET /api/sessions/physical-session-1/messages',
      ]);
      expect(controller.sessionId, 'physical-session-1');
      expect(controller.messages.map((message) => message.text), [
        '跑了两公里',
        '已记录跑步。',
        '刚才那个是多少？',
        '刚才记录的是两公里。',
      ]);

      await controller.send('把刚才那个改成三公里');

      expect(turns, hasLength(1));
      expect(turns.single.$1, '/api/chat');
      expect(turns.single.$2, {
        'session_id': 'physical-session-1',
        'user_text': '把刚才那个改成三公里',
      });
      expect(controller.messages[4].inputTurnId, 'turn-typed-2');
      final agent = controller.messages.last;
      expect(agent.text, '改好啦，跑步距离是 3 公里。');
      expect(agent.inputTurnId, 'turn-typed-2');
      expect(
        agent.parts.whereType<ToolCallPart>().single.name,
        'tool_update_asset',
      );
      expect(
        agent.parts.whereType<ToolResultPart>().single.response['ok'],
        isTrue,
      );
      expect(agent.elapsedMs, 120);
      expect(agent.tokens, 42);
    },
  );

  test('chat stream failure stays on the failed turn', () async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((_) async => http.Response('not used', 500)),
    );
    final controller = CaptureSessionController(
      api: api,
      turnStream: (_, _) => Stream<SseEvent>.error(StateError('offline')),
    )..sessionId = 'physical-session-1';
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.send('测试失败');

    expect(controller.streaming, isFalse);
    expect(controller.error, isNull);
    expect(
      controller.messages.last.parts.whereType<ErrorPart>().single.message,
      '发送失败，请稍后重试',
    );
  });

  testWidgets('flash header counts hardware recordings, not typed chat turns', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.url.path == '/api/flash/sessions/2026-08-05') {
          return http.Response(
            jsonEncode({
              'session': {
                'id': '2026-08-05',
                'date': '2026-08-05',
                'physical_session_id': 'physical-session-1',
                'recordings': [
                  {
                    'id': 'recording-1',
                    'process_status': 'done',
                    'asr_text': '硬件闪念',
                    'input_turn_id': 'turn-voice-1',
                    'result_cards': const [],
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/sessions/physical-session-1/messages') {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'id': 'voice-user-1',
                  'role': 'user',
                  'status': 'done',
                  'text': '硬件闪念',
                  'input_turn_id': 'turn-voice-1',
                  'cards': const [],
                },
                {
                  'id': 'typed-user-1',
                  'role': 'user',
                  'status': 'done',
                  'text': '这是一条会话消息',
                  'input_turn_id': 'turn-typed-1',
                  'cards': const [],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );
    final controller = CaptureSessionController(api: api);
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    await controller.loadSession('2026-08-05');

    await tester.pumpWidget(
      MaterialApp(
        home: ThemeV2SessionPage(
          controller: controller,
          initializeController: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('01'), findsNWidgets(2));
    expect(find.text('02'), findsNothing);
  });
}
