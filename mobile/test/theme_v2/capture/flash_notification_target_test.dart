import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/pages/session_detail_page.dart';
import 'package:eureka/render/render_spec.dart';
import 'package:eureka/theme_v2/capture/capture_session_controller.dart';
import 'package:eureka/theme_v2/capture/capture_session_page.dart';
import 'package:eureka/theme_v2/capture/flash_notification_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Theme V2 library deep-link resolves to its recording session', () {
    const recordingId = 'd727c76c-2d36-4b1f-8507-7f84c5a3e242';
    const link = '/library?recording_id=$recordingId';

    expect(flashRecordingIdFromLink(link), recordingId);
    final page = flashNotificationTargetPage(link);
    expect(page, isA<CaptureSessionPage>());
    expect((page as CaptureSessionPage).recordingId, recordingId);
  });

  test('legacy bare session id keeps the legacy session target', () {
    const sessionId = 'legacy-session-id';

    expect(flashRecordingIdFromLink(sessionId), isNull);
    final page = flashNotificationTargetPage(sessionId);
    expect(page, isA<SessionDetailPage>());
    expect((page as SessionDetailPage).sessionId, sessionId);
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
        '/api/events/event-1',
        '/api/assets/asset-1',
      ]);
      expect(controller.sessionId, 'recording-1');
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
              request.url.path == '/api/flash/recordings') {
            return http.Response(
              jsonEncode({
                'recordings': [
                  {
                    'id': 'recording-1',
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
          if (request.method == 'POST' && request.url.path == '/api/flash') {
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            expect(payload['session_id'], 'recording-1');
            expect(payload['source'], 'typed');
            return http.Response(
              jsonEncode({
                'ok': true,
                'session_id': 'recording-2',
                'input_turn_id': 'turn-2',
                'summary': '已继续整理。',
                'cards': const [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/flash/recordings/recording-2') {
            return http.Response(
              jsonEncode({
                'recording': {
                  'id': 'recording-2',
                  'process_status': 'done',
                  'asr_text': '继续整理',
                  'input_turn_id': 'turn-2',
                  'result_summary': '已继续整理。',
                  'result_cards': const [],
                  'created_at': '2026-08-02T14:00:00Z',
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
      controller.sessionId = 'recording-1';

      final sessions = await controller.listSessions();
      expect(sessions.single.id, 'recording-1');
      expect(await controller.deleteSession('recording-old'), isTrue);
      await controller.send('继续整理');

      expect(controller.sessionId, 'recording-2');
      expect(controller.messages.first.text, '继续整理');
      expect(controller.messages.last.text, '已继续整理。');
      expect(requested, contains('GET /api/flash/recordings'));
      expect(requested, contains('POST /api/flash'));
    },
  );
}
