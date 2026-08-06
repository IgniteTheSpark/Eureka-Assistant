import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/api/sse_client.dart';
import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/render/render_spec.dart';
import 'package:eureka/render/skill_card.dart';
import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:eureka/theme_v2/capture/capture_session_controller.dart';
import 'package:eureka/theme_v2/capture/capture_session_page.dart';
import 'package:eureka/theme_v2/capture/flash_notification_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('contact skill asset cards open through the asset API', () {
    final card = {
      'card_type': 'contact',
      'asset_id': 'contact-asset-1',
      'user_skill_name': 'contact',
      'payload': {'name': 'Kevin', 'company': '谷歌'},
    };
    final reference = skillCardEntityRef(card);
    final data = resolveSkillCardData(card, {
      'contact': synthesizeSpec('contact'),
    });

    expect(reference?.kind, AssetEntityKind.asset);
    expect(reference?.id, 'contact-asset-1');
    expect(data.title, 'Kevin');
  });

  test('persisted built-in card snapshots use canonical icons', () {
    final expense = resolveSkillCardData({
      'card_type': 'expense',
      'title': '咖啡',
      'icon': '🍔',
      'accent_color': 'green',
      'meta_fields': const [],
    }, const {});
    final contact = resolveSkillCardData({
      'card_type': 'contact',
      'title': 'Alex',
      'icon': '🪪',
      'accent_color': 'neutral',
      'meta_fields': const [],
    }, const {});

    expect(expense.icon, '💳');
    expect(contact.icon, '👤');
  });

  test('Theme V2 library deep-link resolves to its recording session', () {
    const recordingId = 'd727c76c-2d36-4b1f-8507-7f84c5a3e242';
    const link = '/library?recording_id=$recordingId';

    expect(flashRecordingIdFromLink(link), recordingId);
    final page = flashNotificationTargetPage(link);
    expect(page, isA<CaptureSessionPage>());
    expect((page as CaptureSessionPage).recordingId, recordingId);
  });

  test('bare flash session id uses the unified Theme V2 session target', () {
    const sessionId = 'legacy-session-id';

    expect(flashRecordingIdFromLink(sessionId), isNull);
    final page = flashNotificationTargetPage(sessionId);
    expect(page, isA<CaptureSessionPage>());
    expect((page as CaptureSessionPage).recordingId, sessionId);
  });

  test(
    'capture session controller replays transcript, summary and records',
    () async {
      final requestedPaths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://test',
        enableLogging: false,
        client: MockClient((request) async {
          requestedPaths.add(request.url.path);
          switch (request.url.path) {
            case '/api/flash/recordings/recording-1':
              return http.Response(
                jsonEncode({
                  'recording': {
                    'id': 'recording-1',
                    'process_status': 'done',
                    'asr_text': '明天下午三点评审方案，并记下咖啡花了 28 元。',
                    'input_turn_id': 'turn-1',
                    'result_summary': '已创建评审日程并记录咖啡消费。',
                    'result_cards': [
                      {'kind': 'event', 'event_id': 'event-1'},
                      {
                        'kind': 'asset',
                        'asset_id': 'asset-1',
                        'skill_machine_name': 'expense',
                      },
                    ],
                    'created_at': '2026-08-02T13:43:21',
                  },
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            case '/api/events/event-1':
              return http.Response(
                jsonEncode({
                  'id': 'event-1',
                  'title': '评审方案',
                  'start_at': '2026-08-03T15:00:00',
                  'end_at': '2026-08-03T16:00:00',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            case '/api/assets/asset-1':
              return http.Response(
                jsonEncode({
                  'id': 'asset-1',
                  'user_skill_id': 'expense-skill',
                  'payload': {
                    'amount': 28,
                    'currency': 'CNY',
                    'category': '咖啡',
                  },
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

      await controller.loadSession('recording-1');

      expect(requestedPaths, [
        '/api/flash/recordings/recording-1',
        '/api/flash/sessions/2026-08-02',
        '/api/events/event-1',
        '/api/assets/asset-1',
      ]);
      expect(controller.sessionId, '2026-08-02');
      expect(controller.displayTitle, '8月2日 闪念');
      expect(controller.messages, hasLength(2));
      expect(controller.messages.first.text, contains('咖啡花了 28 元'));
      expect(controller.messages.first.inputTurnId, 'turn-1');
      final agent = controller.messages.last;
      expect(agent.text, '已创建评审日程并记录咖啡消费。');
      final cards = agent.parts.whereType<CardsPart>().single.cards;
      expect(cards[0], containsPair('card_type', 'event'));
      expect(cards[0], containsPair('title', '评审方案'));
      expect(cards[1], containsPair('card_type', 'expense'));
      expect(cards[1]['payload'], containsPair('amount', 28));
    },
  );

  test(
    'Theme V2 render specs use core user-skills without legacy 404',
    () async {
      final requestedPaths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://test',
        enableLogging: false,
        client: MockClient((request) async {
          requestedPaths.add(request.url.path);
          if (request.url.path == '/api/user-skills') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'expense-skill',
                  'machine_name': 'expense',
                  'display_name': '消费',
                  'schema': {
                    'amount': {'type': 'number'},
                    'currency': {'type': 'string'},
                    'description': {'type': 'string'},
                  },
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('legacy endpoint must not be called', 500);
        }),
      );
      addTearDown(api.close);

      final specs = await fetchRenderSpecs(api, coreRecordsOnly: true);

      expect(requestedPaths, ['/api/user-skills']);
      expect(specs['expense']?.primaryField, 'amount');
      expect(specs['expense']?.secondaryField, 'description');
    },
  );

  test('recording deep-link opens the whole daily flash session', () async {
    final requested = <String>[];
    final api = ApiClient(
      baseUrl: 'http://test',
      enableLogging: false,
      client: MockClient((request) async {
        requested.add(request.url.path);
        if (request.url.path == '/api/flash/recordings/recording-2') {
          return http.Response(
            jsonEncode({
              'recording': {
                'id': 'recording-2',
                'created_at': '2026-08-02T14:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/flash/sessions/2026-08-02') {
          return http.Response(
            jsonEncode({
              'session': {
                'id': '2026-08-02',
                'date': '2026-08-02',
                'title': '8月2日 闪念',
                'recordings': [
                  {
                    'id': 'recording-1',
                    'process_status': 'done',
                    'asr_text': '上午的闪念',
                    'input_turn_id': 'turn-1',
                    'result_summary': '已整理上午内容。',
                    'result_cards': const [],
                    'created_at': '2026-08-02T09:00:00Z',
                  },
                  {
                    'id': 'recording-2',
                    'process_status': 'done',
                    'asr_text': '下午的闪念',
                    'input_turn_id': 'turn-2',
                    'result_summary': '已整理下午内容。',
                    'result_cards': const [],
                    'created_at': '2026-08-02T14:00:00Z',
                  },
                ],
                'chat_messages': [
                  {
                    'id': 'chat-user-1',
                    'role': 'user',
                    'text': '今天有什么待办？',
                    'status': 'done',
                    'created_at': '2026-08-02T14:10:00Z',
                  },
                  {
                    'id': 'chat-agent-1',
                    'role': 'agent',
                    'text': '今天有一项待办：提交评审稿。',
                    'status': 'done',
                    'created_at': '2026-08-02T14:10:01Z',
                  },
                ],
              },
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

    await controller.loadSession('recording-2');

    expect(requested, [
      '/api/flash/recordings/recording-2',
      '/api/flash/sessions/2026-08-02',
    ]);
    expect(controller.sessionId, '2026-08-02');
    expect(controller.displayTitle, '8月2日 闪念');
    expect(controller.messages.map((message) => message.text), [
      '上午的闪念',
      '已整理上午内容。',
      '下午的闪念',
      '已整理下午内容。',
      '今天有什么待办？',
      '今天有一项待办：提交评审稿。',
    ]);
  });

  test(
    'failed capture is attached to its own turn, not the session tail',
    () async {
      final api = ApiClient(
        baseUrl: 'http://test',
        enableLogging: false,
        client: MockClient((request) async {
          if (request.url.path == '/api/flash/sessions/2026-08-05') {
            return http.Response(
              jsonEncode({
                'session': {
                  'id': '2026-08-05',
                  'date': '2026-08-05',
                  'recordings': [
                    {
                      'id': 'recording-failed',
                      'process_status': 'failed',
                      'asr_text': '刚刚跑了两公里。',
                      'input_turn_id': 'turn-failed',
                      'error_message': 'invalid capture provider response',
                      'result_cards': const [],
                    },
                    {
                      'id': 'recording-done',
                      'process_status': 'done',
                      'asr_text': '喝了两百毫升水。',
                      'input_turn_id': 'turn-done',
                      'result_summary': '已记录喝水。',
                      'result_cards': const [],
                    },
                  ],
                },
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

      expect(controller.error, isNull);
      expect(controller.messages.map((message) => message.text), [
        '刚刚跑了两公里。',
        '',
        '喝了两百毫升水。',
        '已记录喝水。',
      ]);
      expect(
        controller.messages[1].parts.whereType<ErrorPart>().single.message,
        '整理失败，原始录音已保留',
      );
      expect(controller.messages[1].inputTurnId, 'turn-failed');
      expect(controller.messages[3].parts.whereType<ErrorPart>(), isEmpty);
    },
  );

  test(
    'capture session lists history, deletes, and accepts typed input',
    () async {
      final requested = <String>[];
      final api = ApiClient(
        baseUrl: 'http://test',
        enableLogging: false,
        client: MockClient((request) async {
          requested.add('${request.method} ${request.url.path}');
          if (request.method == 'GET' &&
              request.url.path == '/api/flash/sessions') {
            return http.Response(
              jsonEncode({
                'sessions': [
                  {
                    'id': '2026-08-02',
                    'date': '2026-08-02',
                    'physical_session_id': 'physical-session-2',
                    'title': '8月2日 闪念',
                    'created_at': '2026-08-02T13:43:21Z',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'DELETE') {
            return http.Response('{}', 200);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/flash/sessions/2026-08-02') {
            return http.Response(
              jsonEncode({
                'session': {
                  'id': '2026-08-02',
                  'date': '2026-08-02',
                  'recordings': [
                    {
                      'id': 'recording-2',
                      'process_status': 'done',
                      'asr_text': '继续整理',
                      'input_turn_id': 'turn-2',
                      'result_summary': '已继续整理。',
                      'result_cards': const [],
                      'created_at': '2026-08-02T14:00:00Z',
                    },
                  ],
                },
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
          expect(path, '/api/chat');
          expect(body, {
            'session_id': 'physical-session-2',
            'user_text': '今天有什么待办？',
          });
          return Stream<SseEvent>.fromIterable([
            SseEvent('meta', {
              'session_id': 'physical-session-2',
              'input_turn_id': 'chat-user-1',
            }),
            SseEvent('token', {'text': '今天有一项待办：提交评审稿。'}),
            SseEvent('done', const {}),
          ]);
        },
      );
      addTearDown(() {
        controller.dispose();
        api.close();
      });
      controller.sessionId = 'physical-session-2';

      final sessions = await controller.listSessions();
      expect(sessions.single.id, 'physical-session-2');
      expect(await controller.deleteSession('2026-08-01'), isTrue);
      await controller.send('今天有什么待办？');

      expect(controller.sessionId, 'physical-session-2');
      expect(controller.messages.first.text, '今天有什么待办？');
      expect(controller.messages.last.text, '今天有一项待办：提交评审稿。');
      expect(requested, contains('GET /api/flash/sessions'));
      expect(requested, contains('DELETE /api/flash/sessions/2026-08-01'));
      expect(
        requested,
        isNot(contains('POST /api/flash/sessions/2026-08-02/chat')),
      );
    },
  );

  test('capture session reports chat failures without throwing', () async {
    final api = ApiClient(
      baseUrl: 'http://test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/flash/sessions/2026-08-02/chat') {
          return http.Response('upstream unavailable', 503);
        }
        return http.Response('not found', 404);
      }),
    );
    final controller = CaptureSessionController(
      api: api,
      turnStream: (_, _) =>
          Stream<SseEvent>.error(StateError('upstream unavailable')),
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });
    controller.sessionId = 'physical-session-2';

    await controller.send('今天有什么待办？');

    expect(controller.streaming, isFalse);
    expect(controller.error, isNull);
    expect(controller.messages.first.text, '今天有什么待办？');
    expect(
      controller.messages.last.parts.whereType<ErrorPart>().single.message,
      '发送失败，请稍后重试',
    );
  });
}
