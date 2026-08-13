import 'dart:async';
import 'dart:convert';

import 'package:eureka/api/api_client.dart';
import 'package:eureka/api/sse_client.dart';
import 'package:eureka/capture_activity/capture_activity_event.dart';
import 'package:eureka/chat/chat_models.dart';
import 'package:eureka/theme_v2/capture/capture_activity_coordinator.dart';
import 'package:eureka/theme_v2/capture/capture_session_controller.dart';
import 'package:eureka/theme_v2/session/session_invalidation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'matching newer invalidation debounces and refetches the open session',
    () async {
      final invalidations = ValueNotifier<SessionInvalidation?>(null);
      final activities = CaptureActivityCoordinator();
      var dailyLoads = 0;
      final api = ApiClient(
        baseUrl: 'http://theme-v2.test',
        enableLogging: false,
        client: MockClient((request) async {
          if (request.url.path == '/api/flash/sessions/2026-08-05') {
            dailyLoads++;
            return http.Response(
              jsonEncode({
                'session': {
                  'id': '2026-08-05',
                  'date': '2026-08-05',
                  'physical_session_id': 'physical-session-1',
                  'session_revision': dailyLoads,
                  'recordings': [
                    {
                      'id': 'recording-1',
                      'asr_text': '跑了两公里',
                      'process_status': dailyLoads == 1
                          ? 'asr_processing'
                          : 'done',
                      'result_summary': dailyLoads == 1 ? '' : '已记录跑步。',
                      'result_cards': const [],
                      'input_turn_id': 'turn-1',
                    },
                  ],
                  'chat_messages': const [],
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
                    'id': 'capture-user-1',
                    'role': 'user',
                    'status': 'done',
                    'text': '跑了两公里',
                    'input_turn_id': 'turn-1',
                    'cards': const [],
                  },
                  {
                    'id': 'capture-agent-1',
                    'role': 'agent',
                    'status': dailyLoads == 1 ? 'running' : 'done',
                    'text': dailyLoads == 1 ? '' : '已记录跑步。',
                    'input_turn_id': 'turn-1',
                    'cards': const [],
                    if (dailyLoads > 1) 'elapsed_ms': 1420,
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
        invalidations: invalidations,
        activityCoordinator: activities,
        invalidationDebounce: const Duration(milliseconds: 10),
      );
      addTearDown(() {
        controller.dispose();
        api.close();
        invalidations.dispose();
        activities.dispose();
      });

      await controller.loadSession('2026-08-05');
      expect(dailyLoads, 1);
      expect(controller.streaming, isTrue);
      expect(controller.messages.last.processingStartedAt, isNull);

      activities.apply(
        CaptureActivityEvent(
          aliases: const {'client:ring-task-1'},
          source: CaptureActivitySource.ring,
          phase: CaptureActivityPhase.listening,
          isRealtime: true,
          occurredAt: DateTime.utc(2026, 8, 5, 1),
        ),
      );
      expect(controller.transientCapturePhase, CaptureActivityPhase.listening);
      expect(controller.messages.last.processingStartedAt, isNull);

      activities.apply(
        CaptureActivityEvent(
          aliases: const {'client:ring-task-1'},
          source: CaptureActivitySource.ring,
          phase: CaptureActivityPhase.transcribing,
          isRealtime: true,
          occurredAt: DateTime.utc(2026, 8, 5, 1, 1),
        ),
      );
      expect(
        controller.transientCapturePhase,
        CaptureActivityPhase.transcribing,
      );
      expect(controller.messages.last.processingStartedAt, isNull);

      activities.apply(
        CaptureActivityEvent(
          aliases: const {'client:ring-task-1', 'recording:recording-1'},
          source: CaptureActivitySource.ring,
          phase: CaptureActivityPhase.understanding,
          isRealtime: true,
          sessionId: 'physical-session-1',
          inputTurnId: 'turn-1',
          occurredAt: DateTime.utc(2026, 8, 5, 1, 2),
        ),
      );
      activities.apply(
        CaptureActivityEvent(
          aliases: const {'recording:recording-1'},
          source: CaptureActivitySource.ring,
          phase: CaptureActivityPhase.organizing,
          isRealtime: true,
          sessionId: 'physical-session-1',
          inputTurnId: 'turn-1',
          occurredAt: DateTime.utc(2026, 8, 5, 1, 3),
        ),
      );
      expect(controller.transientCapturePhase, isNull);
      expect(controller.messages.last.workPhase, AgentWorkPhase.organizing);
      expect(
        controller.messages.last.processingStartedAt,
        DateTime.utc(2026, 8, 5, 1, 2),
      );

      invalidations.value = const SessionInvalidation(
        sessionId: 'another-session',
        sessionDate: '2026-08-04',
        revision: 9,
        reason: 'capture_agent_done',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(dailyLoads, 1);

      invalidations.value = const SessionInvalidation(
        sessionId: 'physical-session-1',
        sessionDate: '2026-08-05',
        revision: 2,
        reason: 'capture_agent_done',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(dailyLoads, 2);
      expect(controller.streaming, isFalse);
      expect(controller.messages.last.text, '已记录跑步。');
      expect(controller.messages.last.elapsedMs, 1420);
    },
  );

  test('agent-processing recovery starts a local fallback stopwatch', () async {
    final fallbackNow = DateTime.utc(2026, 8, 5, 2);
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
                'recordings': const [
                  {
                    'id': 'recording-1',
                    'asr_text': '跑了两公里',
                    'process_status': 'agent_processing',
                    'input_turn_id': 'turn-1',
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
              'messages': const [
                {
                  'id': 'capture-agent-1',
                  'role': 'agent',
                  'status': 'running',
                  'text': '',
                  'input_turn_id': 'turn-1',
                  'cards': [],
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
      now: () => fallbackNow,
    );
    addTearDown(() {
      controller.dispose();
      api.close();
    });

    await controller.loadSession('2026-08-05');

    expect(controller.messages.single.processingStartedAt, fallbackNow);
  });

  test('background refresh preserves a typed follow-up stopwatch', () async {
    final invalidations = ValueNotifier<SessionInvalidation?>(null);
    final turnEvents = StreamController<SseEvent>();
    var now = DateTime.utc(2026, 8, 5, 3);
    var dailyLoads = 0;
    final api = ApiClient(
      baseUrl: 'http://theme-v2.test',
      enableLogging: false,
      client: MockClient((request) async {
        if (request.url.path == '/api/flash/sessions/2026-08-05') {
          dailyLoads++;
          return http.Response(
            jsonEncode({
              'session': {
                'id': '2026-08-05',
                'date': '2026-08-05',
                'physical_session_id': 'physical-session-1',
                'session_revision': dailyLoads,
                'recordings': const [
                  {
                    'id': 'recording-1',
                    'asr_text': '跑了两公里',
                    'process_status': 'done',
                    'input_turn_id': 'turn-voice-1',
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
                const {
                  'id': 'voice-agent-1',
                  'role': 'agent',
                  'status': 'done',
                  'text': '已记录跑步。',
                  'input_turn_id': 'turn-voice-1',
                  'cards': [],
                },
                if (dailyLoads > 1) ...const [
                  {
                    'id': 'typed-user-durable',
                    'role': 'user',
                    'status': 'done',
                    'text': '改成三公里',
                    'input_turn_id': 'turn-typed-1',
                    'cards': [],
                  },
                  {
                    'id': 'typed-agent-durable',
                    'role': 'agent',
                    'status': 'running',
                    'text': '',
                    'input_turn_id': 'turn-typed-1',
                    'cards': [],
                  },
                ],
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
      invalidations: invalidations,
      invalidationDebounce: const Duration(milliseconds: 5),
      now: () => now,
      turnStream: (_, _) => turnEvents.stream,
    );
    addTearDown(() async {
      if (!turnEvents.isClosed) await turnEvents.close();
      controller.dispose();
      api.close();
      invalidations.dispose();
    });

    await controller.loadSession('2026-08-05');
    final pending = controller.send('改成三公里');
    await Future<void>.delayed(Duration.zero);
    turnEvents.add(
      SseEvent('meta', {
        'session_id': 'physical-session-1',
        'input_turn_id': 'turn-typed-1',
      }),
    );
    await Future<void>.delayed(Duration.zero);
    final startedAt = controller.messages.last.processingStartedAt;
    expect(startedAt, now);

    now = now.add(const Duration(seconds: 30));
    invalidations.value = const SessionInvalidation(
      sessionId: 'physical-session-1',
      sessionDate: '2026-08-05',
      revision: 2,
      reason: 'chat_turn_created',
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.messages.last.id, 'typed-agent-durable');
    expect(controller.messages.last.processingStartedAt, startedAt);

    await turnEvents.close();
    await pending;
  });
}
